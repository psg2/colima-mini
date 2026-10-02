import ColimaCore
import Combine
import Foundation

package struct PendingAction: Identifiable {
  package let id = UUID()
  package let title: String
  package let message: String
  package let verb: String
  package let containers: [Container]
  package let vm: Bool
  package let compose: ComposeAction?
  // The confirmation button's title.
  package var label: String {
    compose?.title ?? (verb == "rm" ? "Remove" : verb.capitalized)
  }
  package var destructive: Bool { compose?.destructive ?? (verb != "start") }
  package init(
    title: String, message: String, verb: String, containers: [Container], vm: Bool,
    compose: ComposeAction? = nil
  ) {
    self.title = title
    self.message = message
    self.verb = verb
    self.containers = containers
    self.vm = vm
    self.compose = compose
  }
}

@MainActor package final class Dashboard: ObservableObject {
  package let backend: Backend
  private let readSnapshot: () async throws -> Snapshot
  private let streamLogs: (String) -> AsyncThrowingStream<String, Error>
  private let readDetails: (String) async throws -> ContainerDetails
  private let readVolumes: () async throws -> [Volume]
  private var refreshTask: Task<Snapshot, Error>?
  private var refreshGeneration = 0
  private var logGeneration = 0
  private var detailsGeneration = 0
  private var backRoutes: [AppRoute] = []
  // Containers changed by this app recently; their transitions are not alerts.
  private var actedOn: [String: Date] = [:]
  package var onAlerts: (([ContainerAlert]) -> Void)?
  @Published package var route = AppRoute.containers
  @Published package var snapshot: Snapshot?
  @Published package var error: String?
  @Published package var refreshing = false
  @Published package var busy = false
  @Published package var lastRefresh: Date?
  @Published package var selectedID: String?
  @Published package var containerTab = ContainerPageTab.overview
  @Published package var project = "All containers"
  @Published package var search = ""
  @Published package var listScrollID: String?
  @Published package var volumeSearch = ""
  @Published package var imageSearch = ""
  @Published package var unattachedOnly = false
  @Published package var volumeKind = VolumeKind.all
  @Published package var volumeSortBySize = false
  @Published package var logs = ""
  @Published package var logError: String?
  @Published package var logsLoading = false
  @Published package var logsPaused = false
  // True while new output is arriving; false once the stream ended or failed.
  @Published package var logsLive = false
  @Published package var logsDate: Date?
  @Published package var sweepGroups: [SweepGroup]?
  @Published package var sweepError: String?
  @Published package var sweptAt: Date?
  @Published package var scanning = false
  @Published package var showingSweep = false
  @Published package var pending: PendingAction?
  @Published package var onlyRunning = false
  @Published package var grouped = true
  @Published package var collapsed: Set<String> = []
  @Published package var settingsMessage: String?
  @Published package var applyingResources = false
  @Published package var refreshInterval = 5
  @Published package var details: ContainerDetails?
  @Published package var detailsError: String?
  @Published package var detailsLoading = false
  @Published package var detailsDate: Date?
  @Published package var volumes: [Volume] = []
  @Published package var volumesError: String?
  @Published package var volumesLoading = false
  @Published package var volumesDate: Date?
  @Published package var images: [DockerImage] = []
  @Published package var imagesError: String?
  @Published package var imagesLoading = false
  @Published package var imagesDate: Date?
  @Published package var storage: StorageSnapshot?
  @Published package var storageError: String?
  @Published package var storageLoading = false
  @Published package var cleanupPlan: CleanupPlan?
  @Published package var cleanupError: String?
  @Published package var cleanupLoading = false
  @Published package var cleanupResult: CleanupResult?
  @Published package var reclaiming = false
  @Published package var showingReclaim = false
  @Published package var history: [String: [MetricSample]] = [:]
  @Published package var totalHistory: [MetricSample] = []
  @Published package var notificationsEnabled = true

  package init(
    backend: Backend,
    readSnapshot: (() async throws -> Snapshot)? = nil,
    streamLogs: ((String) -> AsyncThrowingStream<String, Error>)? = nil,
    readDetails: ((String) async throws -> ContainerDetails)? = nil,
    readVolumes: (() async throws -> [Volume])? = nil
  ) {
    self.backend = backend
    self.readSnapshot = readSnapshot ?? { try await backend.snapshot() }
    self.streamLogs = streamLogs ?? { backend.followLogs($0) }
    self.readDetails = readDetails ?? { try await backend.details($0) }
    self.readVolumes = readVolumes ?? { try await backend.volumes() }
    if backend.fixture == nil {
      let defaults = UserDefaults.standard
      onlyRunning = defaults.bool(forKey: "onlyRunning")
      grouped = defaults.object(forKey: "grouped") == nil || defaults.bool(forKey: "grouped")
      collapsed = Set(defaults.stringArray(forKey: "collapsedProjects") ?? [])
      let interval = defaults.integer(forKey: "refreshInterval")
      refreshInterval = [5, 10, 30, 60].contains(interval) ? interval : 5
      notificationsEnabled =
        defaults.object(forKey: "notifications") == nil || defaults.bool(forKey: "notifications")
    }
  }
  package func savePreferences() {
    guard !sample else { return }
    let defaults = UserDefaults.standard
    defaults.set(onlyRunning, forKey: "onlyRunning")
    defaults.set(grouped, forKey: "grouped")
    defaults.set(Array(collapsed), forKey: "collapsedProjects")
    defaults.set(refreshInterval, forKey: "refreshInterval")
    defaults.set(notificationsEnabled, forKey: "notifications")
  }
  package func restoreLastSection() {
    guard !sample, let name = UserDefaults.standard.string(forKey: "lastSection") else { return }
    let sections: [AppRoute] = [.overview, .containers, .volumes, .images, .storage]
    if let section = sections.first(where: { $0.sectionName == name }) { route = section }
  }
  package var sample: Bool { backend.fixture != nil }
  package var containers: [Container] { snapshot?.containers ?? [] }
  package var selected: Container? { containers.first { $0.id == selectedID } }
  package var visible: [Container] {
    containers.filter {
      (project == "All containers" || $0.project == project) && (!onlyRunning || $0.running)
        && (search.isEmpty
          || "\($0.name) \($0.image) \($0.project)".localizedCaseInsensitiveContains(search))
    }
  }
  package var allVisibleGroupsCollapsed: Bool {
    !visible.isEmpty && visible.allSatisfy { collapsed.contains($0.project) }
  }
  package func setGroupExpanded(_ project: String, expanded: Bool) {
    guard search.isEmpty else { return }
    if expanded { collapsed.remove(project) } else { collapsed.insert(project) }
    savePreferences()
  }
  package func toggleVisibleGroups() {
    guard search.isEmpty else { return }
    let projects = Set(visible.map(\.project))
    if allVisibleGroupsCollapsed {
      collapsed.subtract(projects)
    } else {
      collapsed.formUnion(projects)
    }
    savePreferences()
  }
  package func navigate(_ target: AppRoute, project: String? = nil) {
    logGeneration += 1
    logsLoading = false
    if let project {
      self.project = project
      search = ""
    }
    route = target
    backRoutes.removeAll()
    selectedID = nil
    if !sample, let name = target.sectionName {
      UserDefaults.standard.set(name, forKey: "lastSection")
    }
  }
  package var attention: [Container] { containers.filter(\.needsAttention) }
  package func origin(of project: String) -> ProjectOrigin? {
    containers.first { $0.project == project && $0.origin != nil }?.origin
  }
  package func openContainer(_ id: String, tab: ContainerPageTab = .overview) {
    if route != .container(id) { backRoutes.append(route) }
    route = .container(id)
    containerTab = tab
    selectedID = id
    detailsGeneration += 1
    detailsLoading = false
    details = nil
    detailsDate = nil
    detailsError = nil
    resetLogs()
  }
  package func openVolume(_ name: String) {
    backRoutes.append(route)
    route = .volume(name)
    logGeneration += 1
    logsLoading = false
  }
  package func openImage(_ id: String) {
    backRoutes.append(route)
    route = .image(id)
  }
  package func goBack() {
    route = backRoutes.popLast() ?? .containers
    if case .container(let id) = route {
      selectedID = id
      containerTab = .overview
      detailsGeneration += 1
      details = nil
      detailsDate = nil
      detailsError = nil
      detailsLoading = false
      resetLogs()
    } else {
      selectedID = nil
      if case .projectLogs = route { resetLogs() }
    }
    logGeneration += 1
    logsLoading = false
  }
  package func resetLogs() {
    logGeneration += 1
    logs = ""
    logError = nil
    logsDate = nil
    logsLoading = false
    logsPaused = false
  }
  package func invalidateRefresh() {
    refreshGeneration += 1
    refreshTask?.cancel()
    refreshTask = nil
    refreshing = false
  }
  // One loop serves the window and the menu bar. It slows down while another
  // app is in front, so background alerts keep working at a lower cost.
  package func poll(isForeground: @escaping () -> Bool) async {
    while !Task.isCancelled {
      await refresh()
      let seconds = isForeground() ? refreshInterval : max(30, refreshInterval)
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
    }
  }
  package func refresh() async {
    guard !refreshing, !busy else { return }
    refreshGeneration += 1
    let generation = refreshGeneration
    refreshing = true
    let task = Task { try await readSnapshot() }
    refreshTask = task
    defer {
      if generation == refreshGeneration {
        refreshing = false
        refreshTask = nil
      }
    }
    do {
      let updated = try await task.value
      guard generation == refreshGeneration, !Task.isCancelled, !busy else { return }
      let previous = snapshot
      snapshot = updated
      publishAlerts(from: previous, to: updated)
      error = nil
      let date = Date()
      lastRefresh = date
      for container in updated.containers {
        if let metric = updated.metric(for: container) {
          var samples = history[container.id] ?? []
          samples.append(MetricSample(date: date, cpu: metric.cpu, memory: metric.memoryBytes))
          history[container.id] = Array(samples.suffix(60))
        }
      }
      history = history.filter { key, _ in updated.containers.contains { $0.id == key } }
      if updated.vm.running {
        totalHistory = Array(
          (totalHistory
            + [
              // Relative to VM capacity, unlike per-container samples.
              MetricSample(
                date: date,
                cpu: updated.totalCPU(updated.containers) / Double(max(1, updated.vm.cpus)),
                memory: updated.totalMemory(updated.containers))
            ]).suffix(60))
      }
      if project != "All containers" && !updated.projects.contains(project) {
        project = "All containers"
      }
    } catch is CancellationError {} catch {
      if generation == refreshGeneration, !Task.isCancelled {
        self.error = error.localizedDescription
      }
    }
  }
  private func publishAlerts(from previous: Snapshot?, to updated: Snapshot) {
    let now = Date()
    actedOn = actedOn.filter { now.timeIntervalSince($0.value) < 120 }
    guard notificationsEnabled, !sample, let previous, previous.vm.running, updated.vm.running
    else { return }
    let alerts = ContainerAlert.changes(from: previous.containers, to: updated.containers)
      .filter { actedOn[$0.containerID] == nil }
    if !alerts.isEmpty { onAlerts?(alerts) }
  }
  // Follows a container's output until the page changes, logs are paused or
  // the container stops. The buffer is replaced only when the new stream
  // produces output, so a failed start keeps the previous lines visible.
  package func followLogs(_ id: String) async {
    await follow(.container(id), streamLogs(id))
  }
  // Every running service of a project in one stream, labeled per service.
  package func followProjectLogs(_ project: String) async {
    let sources = containers.filter { $0.project == project && $0.running }.map {
      LogSource(id: $0.id, label: $0.service)
    }
    guard !sources.isEmpty else { return }
    await follow(.projectLogs(project), backend.followProjectLogs(sources))
  }
  package func openProjectLogs(_ project: String) {
    if route != .projectLogs(project) { backRoutes.append(route) }
    route = .projectLogs(project)
    selectedID = nil
    resetLogs()
  }
  private func follow(_ target: AppRoute, _ stream: AsyncThrowingStream<String, Error>) async {
    let id = target
    guard route == id, !logsPaused else { return }
    logGeneration += 1
    let generation = logGeneration
    var current: String?
    logsLoading = true
    defer {
      if generation == logGeneration {
        logsLoading = false
        logsLive = false
      }
    }
    func valid() -> Bool {
      generation == logGeneration && route == id && !Task.isCancelled && !logsPaused
    }
    do {
      for try await chunk in stream {
        guard valid() else { return }
        let text = (current ?? "") + chunk
        // Keep the newest lines so a chatty container can't grow memory unbounded.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        current =
          lines.count > Self.logLineLimit
          ? lines.suffix(Self.logLineLimit).joined(separator: "\n") : text
        logs = current ?? ""
        logError = nil
        logsDate = Date()
        logsLoading = false
        logsLive = true
      }
    } catch is CancellationError {} catch {
      guard generation == logGeneration, route == id, !Task.isCancelled else { return }
      logError = error.localizedDescription
    }
  }
  package static let logLineLimit = 5_000
  package func loadDetails(_ id: String) async {
    guard route == .container(id) else { return }
    detailsGeneration += 1
    let generation = detailsGeneration
    detailsLoading = true
    defer { if generation == detailsGeneration { detailsLoading = false } }
    do {
      let result = try await readDetails(id)
      guard route == .container(id), generation == detailsGeneration, !Task.isCancelled else {
        return
      }
      details = result
      detailsDate = Date()
      detailsError = nil
    } catch is CancellationError {} catch {
      if route == .container(id), generation == detailsGeneration, !Task.isCancelled {
        detailsError = error.localizedDescription
      }
    }
  }
  package func loadVolumes() async {
    guard !volumesLoading else { return }
    volumesLoading = true
    defer { volumesLoading = false }
    do {
      // Inventory belongs to the shared model, not the page that requested it.
      // A page may disappear while its read continues to populate this cache.
      let task = Task { try await readVolumes() }
      let result = try await task.value
      volumes = result
      volumesDate = Date()
      volumesError = nil
    } catch is CancellationError {} catch { volumesError = error.localizedDescription }
  }
  package func loadImages() async {
    guard !imagesLoading else { return }
    imagesLoading = true
    defer { imagesLoading = false }
    do {
      let task = Task { try await backend.images() }
      let result = try await task.value
      images = result
      imagesDate = Date()
      imagesError = nil
    } catch is CancellationError {} catch { imagesError = error.localizedDescription }
  }
  package func loadStorage() async {
    guard !storageLoading else { return }
    storageLoading = true
    defer { storageLoading = false }
    do {
      let task = Task { try await backend.storage() }
      let result = try await task.value
      storage = result
      storageError = nil
    } catch is CancellationError {} catch { storageError = error.localizedDescription }
  }
  package func openReclaim() {
    cleanupResult = nil
    showingReclaim = true
  }
  package func loadCleanupPlan() async {
    guard !cleanupLoading, !reclaiming else { return }
    cleanupLoading = true
    defer { cleanupLoading = false }
    do {
      let task = Task { try await backend.cleanupPlan() }
      cleanupPlan = try await task.value
      cleanupError = nil
    } catch is CancellationError {} catch {
      cleanupPlan = nil
      cleanupError = error.localizedDescription
    }
  }
  // Removes the previewed items of the chosen kinds, then re-measures. The plan
  // is replaced afterwards, so a second run starts from a fresh preview.
  package func reclaim(_ kinds: Set<CleanupKind>) async {
    guard !sample, !busy, !reclaiming, let plan = cleanupPlan, !kinds.isEmpty else { return }
    invalidateRefresh()
    busy = true
    reclaiming = true
    let now = Date()
    for item in plan.category(.stoppedContainers)?.items ?? [] { actedOn[item.id] = now }
    do {
      let task = Task { try await backend.reclaim(plan, kinds: kinds) }
      cleanupResult = try await task.value
      cleanupError = nil
    } catch { cleanupError = "Cleanup stopped: " + error.localizedDescription }
    reclaiming = false
    busy = false
    cleanupPlan = nil
    await refresh()
    await loadCleanupPlan()
    await loadStorage()
    if !volumes.isEmpty { await loadVolumes() }
    if !images.isEmpty { await loadImages() }
  }
  package func request(_ verb: String, containers: [Container], vm: Bool = false) {
    // Removal never forces: only stopped containers are offered, and Docker
    // refuses one that started since.
    let containers = verb == "rm" ? containers.filter { !$0.running } : containers
    guard !sample, !busy, vm || !containers.isEmpty else { return }
    let targets =
      vm
      ? "Colima" : (containers.count == 1 ? containers[0].name : "\(containers.count) containers")
    pending = PendingAction(
      title: "\(verb == "rm" ? "Remove" : verb.capitalized) \(targets)?",
      message: vm
        ? "This affects every container in Colima. Your Docker volumes are kept."
        : containers.map(\.name).joined(separator: "\n")
          + (verb == "rm"
            ? "\n\nIts logs and container files are deleted. Volumes are kept." : ""),
      verb: verb, containers: containers, vm: vm)
  }
  // Compose runs against the whole project, including services that have no
  // container yet, so the dialog names the folder rather than containers.
  package func requestCompose(_ action: ComposeAction, project: String) {
    let members = containers.filter {
      $0.project == project && $0.label("com.docker.compose.project") != nil
    }
    guard !sample, !busy, let first = members.first else { return }
    let folder = first.origin?.displayPath ?? "an unknown folder"
    pending = PendingAction(
      title: "\(action.title) \(project)?",
      message: action.explanation + "\n\nFolder: " + folder,
      verb: "compose", containers: members, vm: false, compose: action)
  }
  package func perform(_ action: PendingAction) async {
    guard !busy, !sample else { return }
    invalidateRefresh()
    busy = true
    error = nil
    pending = nil
    let now = Date()
    for container in action.vm ? containers : action.containers { actedOn[container.id] = now }
    var actionError: String?
    do {
      if let compose = action.compose, let first = action.containers.first {
        let project = try await backend.composeProject(first.project, containerID: first.id)
        try await backend.compose(compose, project: project)
      } else if action.vm {
        _ = try await backend.vm(action.verb)
      } else if !action.containers.isEmpty {
        _ = try await backend.docker([action.verb] + action.containers.map(\.id), timeout: 90)
      }
    } catch { actionError = error.localizedDescription }
    busy = false
    await refresh()
    if case .container(let id) = route {
      if action.verb == "rm", !containers.contains(where: { $0.id == id }) {
        goBack()
      } else {
        await loadDetails(id)
      }
    }
    if let actionError { error = actionError }
  }
  package func changeResources(_ resources: ResourceSettings, restart: Bool) async {
    guard !busy, !sample, snapshot != nil else { return }
    invalidateRefresh()
    busy = true
    applyingResources = true
    settingsMessage = nil
    let now = Date()
    for container in containers { actedOn[container.id] = now }
    defer {
      applyingResources = false
      busy = false
    }
    do {
      try await backend.apply(resources, restart: restart)
      settingsMessage =
        restart
        ? "Resources applied. Previously running containers were restored."
        : "Saved. These resources take effect the next time Colima starts."
    } catch { settingsMessage = "Could not apply resources: " + error.localizedDescription }
    busy = false
    await refresh()
  }
  package func scan() async {
    guard !scanning, !busy else { return }
    scanning = true
    showingSweep = true
    defer { scanning = false }
    sweepError = nil
    do {
      sweepGroups = try await backend.unusedContainers()
      sweptAt = Date()
    } catch {
      sweepError = "Scan failed: " + error.localizedDescription
    }
  }
  // The group's containers as they are now, so a row reflects actions taken
  // since the scan and drops out once its containers are gone.
  package func members(of group: SweepGroup) -> [Container] {
    containers.filter { container in
      group.containerIDs.contains { $0.hasPrefix(container.id) || container.id.hasPrefix($0) }
    }
  }
}
