import AppKit
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct PendingAction: Identifiable {
  let id = UUID()
  let title: String
  let message: String
  let verb: String
  let containers: [Container]
  let vm: Bool
}

@MainActor final class Dashboard: ObservableObject {
  let backend: Backend
  @Published var snapshot: Snapshot?
  @Published var error: String?
  @Published var refreshing = false
  @Published var busy = false
  @Published var lastRefresh: Date?
  @Published var selectedID: String?
  @Published var project = "All containers"
  @Published var search = ""
  @Published var logs = "Select a container to view its logs."
  @Published var logError: String?
  @Published var logsLoading = false
  @Published var sweepReport = "Run a scan to find orphaned, stale or idle containers."
  @Published var scanning = false
  @Published var showingSweep = false
  @Published var pending: PendingAction?
  @Published var onlyRunning = false
  @Published var grouped = true
  @Published var collapsed: Set<String> = []
  @Published var settingsMessage: String?
  @Published var applyingResources = false
  @Published var refreshInterval = 5
  init(backend: Backend) {
    self.backend = backend
    if backend.fixture == nil {
      let defaults = UserDefaults.standard
      onlyRunning = defaults.bool(forKey: "onlyRunning")
      grouped = defaults.object(forKey: "grouped") == nil || defaults.bool(forKey: "grouped")
      collapsed = Set(defaults.stringArray(forKey: "collapsedProjects") ?? [])
      let interval = defaults.integer(forKey: "refreshInterval")
      refreshInterval = [5, 10, 30, 60].contains(interval) ? interval : 5
    }
  }
  func savePreferences() {
    guard !sample else { return }
    let defaults = UserDefaults.standard
    defaults.set(onlyRunning, forKey: "onlyRunning")
    defaults.set(grouped, forKey: "grouped")
    defaults.set(Array(collapsed), forKey: "collapsedProjects")
    defaults.set(refreshInterval, forKey: "refreshInterval")
  }
  func changeResources(_ resources: ResourceSettings, restart: Bool) async {
    guard !busy, !sample, let snapshot else { return }
    busy = true
    applyingResources = true
    settingsMessage = nil
    defer {
      busy = false
      applyingResources = false
    }
    do {
      try await backend.apply(resources, restart: restart, snapshot: snapshot)
      settingsMessage =
        restart
        ? "Resources applied. Previously running containers were restored."
        : "Saved. These resources take effect the next time Colima starts."
    } catch { settingsMessage = "Could not apply resources: " + error.localizedDescription }
    busy = false
    await refresh()
  }
  var sample: Bool { backend.fixture != nil }
  var containers: [Container] { snapshot?.containers ?? [] }
  var selected: Container? { containers.first { $0.id == selectedID } }
  var visible: [Container] {
    containers.filter {
      (project == "All containers" || $0.project == project) && (!onlyRunning || $0.running)
        && (search.isEmpty
          || "\($0.name) \($0.image) \($0.project)".localizedCaseInsensitiveContains(search))
    }
  }
  func refresh() async {
    guard !refreshing, !busy else { return }
    refreshing = true
    defer { refreshing = false }
    do {
      let updated = try await backend.snapshot()
      guard !Task.isCancelled else { return }
      snapshot = updated
      error = nil
      lastRefresh = Date()
      if let selectedID, !updated.containers.contains(where: { $0.id == selectedID }) {
        self.selectedID = nil
      }
      if project != "All containers" && !updated.projects.contains(project) {
        project = "All containers"
      }
    } catch is CancellationError {} catch { self.error = error.localizedDescription }
  }
  func loadLogs(_ id: String) async {
    logsLoading = true
    defer { if selectedID == id { logsLoading = false } }
    do {
      let text = try await backend.logs(id)
      guard selectedID == id, !Task.isCancelled else { return }
      logs = text.isEmpty ? "This container has not written any logs." : text
      logError = nil
    } catch is CancellationError {} catch {
      guard selectedID == id else { return }
      logError = error.localizedDescription
    }
  }
  func request(_ verb: String, containers: [Container], vm: Bool = false) {
    guard !sample, !busy else { return }
    let targets =
      vm
      ? "Colima" : (containers.count == 1 ? containers[0].name : "\(containers.count) containers")
    let title = "\(verb.capitalized) \(targets)?"
    let message =
      vm
      ? "This affects every container in Colima. Your Docker volumes are kept."
      : containers.map(\.name).joined(separator: "\n")
    pending = PendingAction(
      title: title, message: message, verb: verb, containers: containers, vm: vm)
  }
  func perform(_ action: PendingAction) async {
    guard !busy, !sample else { return }
    busy = true
    error = nil
    pending = nil
    do {
      if action.vm {
        _ = try await backend.vm(action.verb)
      } else if !action.containers.isEmpty {
        _ = try await backend.docker([action.verb] + action.containers.map(\.id), timeout: 90)
      }
    } catch { self.error = error.localizedDescription }
    busy = false
    let actionError = error
    await refresh()
    if let actionError { error = actionError }
  }
  func scan() async {
    guard !scanning else { return }
    scanning = true
    showingSweep = true
    defer { scanning = false }
    do { sweepReport = try await backend.sweep() } catch {
      sweepReport = error.localizedDescription
    }
  }
}
