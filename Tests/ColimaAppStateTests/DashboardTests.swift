import ColimaAppState
import ColimaCore
import Foundation
import XCTest

private actor ResultGate<Value> {
  private var readers: [CheckedContinuation<Value, Error>] = []
  private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
  func read() async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
      readers.append(continuation)
      for (count, waiter) in waiters where readers.count >= count { waiter.resume() }
      waiters.removeAll { readers.count >= $0.0 }
    }
  }
  func waitForReaders(_ count: Int) async {
    if readers.count >= count { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
  }
  func finish(_ index: Int, with value: Value) { readers[index].resume(returning: value) }
}

@MainActor final class DashboardTests: XCTestCase {
  private func snapshot(running: Bool = true) throws -> Snapshot {
    let vm = #"{"name":"default","status":"Running","cpus":10,"memory":21474836480}"#
    let containers = """
      {"ID":"abc123","Names":"demo-postgres-1","Image":"postgres:18","State":"\(running ? "running" : "exited")","Status":"\(running ? "Up 1 hour" : "Exited (0)")","Ports":"","Labels":"com.docker.compose.project=demo,com.docker.compose.service=postgres"}
      {"ID":"def456","Names":"other-web-1","Image":"web:latest","State":"running","Status":"Up 1 hour","Ports":"","Labels":"com.docker.compose.project=other"}
      """
    return try Snapshot.decode(vm: vm, containers: containers, stats: "")
  }
  private func backend() -> Backend {
    Backend(
      toolchain: Toolchain(environment: [
        "COLIMA_MINI_DOCKER": "/usr/bin/true", "COLIMA_MINI_COLIMA": "/usr/bin/true",
      ]))
  }
  func testOnlyProjectsWhoseFolderIsGoneAreOrphaned() async throws {
    let present = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: present, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: present) }
    let vm = #"{"name":"default","status":"Running","cpus":10,"memory":21474836480}"#
    let containers = """
      {"ID":"a1","Names":"kept-web-1","Image":"web","State":"running","Status":"Up","Ports":"","Labels":"com.docker.compose.project=kept,com.docker.compose.project.working_dir=\(present.path)"}
      {"ID":"b2","Names":"gone-web-1","Image":"web","State":"exited","Status":"Exited (0)","Ports":"","Labels":"com.docker.compose.project=gone,com.docker.compose.project.working_dir=/nonexistent/\(UUID().uuidString)"}
      {"ID":"c3","Names":"loose","Image":"web","State":"running","Status":"Up","Ports":"","Labels":""}
      """
    let model = Dashboard(backend: backend())
    model.snapshot = try Snapshot.decode(vm: vm, containers: containers, stats: "")
    XCTAssertEqual(model.orphanedProjects, ["gone"])
  }
  func testOldRefreshCannotOverwriteCompletedStop() async throws {
    let gate = ResultGate<Snapshot>()
    let model = Dashboard(backend: backend(), readSnapshot: { try await gate.read() })
    let before = try snapshot()
    model.snapshot = before
    let oldRefresh = Task { await model.refresh() }
    await gate.waitForReaders(1)
    let stop = Task {
      await model.perform(
        PendingAction(
          title: "Stop", message: "", verb: "stop", containers: [before.containers[0]], vm: false))
    }
    await gate.waitForReaders(2)
    await gate.finish(1, with: try snapshot(running: false))
    await stop.value
    XCTAssertEqual(model.containers.first?.running, false)
    await gate.finish(0, with: before)
    await oldRefresh.value
    XCTAssertEqual(model.containers.first?.running, false)
    XCTAssertFalse(model.refreshing)
  }
  func testOldLogsCannotReplaceNewContainerPage() async throws {
    var continuations: [String: AsyncThrowingStream<String, Error>.Continuation] = [:]
    let model = Dashboard(
      backend: backend(),
      streamLogs: { id in AsyncThrowingStream { continuations[id] = $0 } })
    model.openContainer("abc123")
    let oldLogs = Task { await model.followLogs("abc123") }
    while continuations["abc123"] == nil { await Task.yield() }
    model.openContainer("def456")
    let newLogs = Task { await model.followLogs("def456") }
    while continuations["def456"] == nil { await Task.yield() }
    continuations["def456"]?.yield("current container log")
    continuations["abc123"]?.yield("old container log")
    continuations["abc123"]?.finish()
    await oldLogs.value
    continuations["def456"]?.finish()
    await newLogs.value
    XCTAssertEqual(model.logs, "current container log")
    XCTAssertFalse(model.logsLoading)
    XCTAssertFalse(model.logsLive)
  }
  func testFollowedLogsKeepOnlyTheNewestLines() async throws {
    let lines = (1...(Dashboard.logLineLimit + 10)).map { "line \($0)" }
    let model = Dashboard(
      backend: backend(),
      streamLogs: { _ in
        AsyncThrowingStream {
          for line in lines { $0.yield(line + "\n") }
          $0.finish()
        }
      })
    model.openContainer("abc123")
    await model.followLogs("abc123")
    let kept = model.logs.split(separator: "\n")
    XCTAssertEqual(kept.last, "line \(Dashboard.logLineLimit + 10)")
    XCTAssertLessThanOrEqual(kept.count, Dashboard.logLineLimit)
  }
  func testBackRestoresProjectSearchCollapseAndScrollContext() async throws {
    let model = Dashboard(backend: backend())
    model.navigate(.containers, project: "demo")
    model.search = "postgres"
    model.collapsed = ["other"]
    model.listScrollID = "demo"
    model.openContainer("abc123")
    model.openVolume("demo_db")
    model.goBack()
    XCTAssertEqual(model.route, .container("abc123"))
    model.goBack()
    XCTAssertEqual(model.route, .containers)
    XCTAssertEqual(model.project, "demo")
    XCTAssertEqual(model.search, "postgres")
    XCTAssertEqual(model.collapsed, ["other"])
    XCTAssertEqual(model.listScrollID, "demo")
  }
  func testGroupControlHandlesMixedGroupsAndSearchWithoutErasingPreferences() async throws {
    let state = try snapshot()
    let fixture = try JSONDecoder().decode(
      Fixture.self, from: Data(#"{"vm":"","containers":"","stats":""}"#.utf8))
    let model = Dashboard(backend: Backend(fixture: fixture))
    model.snapshot = state
    model.collapsed = ["other"]
    model.toggleVisibleGroups()
    XCTAssertTrue(model.allVisibleGroupsCollapsed)
    model.search = "postgres"
    model.setGroupExpanded("demo", expanded: true)
    model.toggleVisibleGroups()
    XCTAssertEqual(model.collapsed, ["demo", "other"])
    model.search = ""
    model.toggleVisibleGroups()
    XCTAssertTrue(model.collapsed.isEmpty)
  }
  func testRemovedContainerKeepsRecoverableRoute() async throws {
    let model = Dashboard(
      backend: backend(),
      readSnapshot: {
        try Snapshot.decode(
          vm: #"{"name":"default","status":"Running","cpus":10,"memory":21474836480}"#,
          containers: "", stats: "")
      })
    model.openContainer("abc123")
    await model.refresh()
    XCTAssertEqual(model.route, .container("abc123"))
    XCTAssertNil(model.selected)
    model.goBack()
    XCTAssertEqual(model.route, .containers)
  }
  func testLogErrorsRetainLastGoodBufferAndPauseDoesNotReplaceIt() async throws {
    let model = Dashboard(
      backend: backend(),
      streamLogs: { _ in
        AsyncThrowingStream { $0.finish(throwing: AppError.message("Daemon unavailable")) }
      })
    model.openContainer("abc123")
    model.logs = "last good log"
    await model.followLogs("abc123")
    XCTAssertEqual(model.logs, "last good log")
    XCTAssertEqual(model.logError, "Daemon unavailable")
    model.logsPaused = true
    await model.followLogs("abc123")
    XCTAssertEqual(model.logs, "last good log")
    XCTAssertFalse(model.logsLoading)
  }
  func testFailedActionRemainsVisibleAfterSuccessfulRefresh() async throws {
    let backend = Backend(
      toolchain: Toolchain(environment: ["COLIMA_MINI_DOCKER": "/usr/bin/false"]))
    let model = Dashboard(backend: backend, readSnapshot: { try self.snapshot() })
    await model.perform(
      PendingAction(
        title: "Stop", message: "", verb: "stop", containers: [try snapshot().containers[0]],
        vm: false))
    XCTAssertNotNil(model.error)
    XCTAssertFalse(model.busy)
    XCTAssertNotNil(model.snapshot)
  }
  private func detail(_ id: String, exitCode: Int = 0) throws -> ContainerDetails {
    try JSONDecoder().decode(
      ContainerDetails.self,
      from: Data(
        """
        {"id":"\(id)","name":"container-\(id)","image":"postgres:18","imageID":"sha256:test","state":{"exitCode":\(exitCode)},"ports":[],"mounts":[]}
        """.utf8))
  }
  func testBackToEarlierContainerClearsOtherDetailsAndPausedLogs() async throws {
    let model = Dashboard(backend: backend())
    model.openContainer("abc123")
    model.openVolume("demo_db")
    model.openContainer("def456")
    model.details = try detail("def456")
    model.logs = "other container's output"
    model.logError = "old log error"
    model.logsPaused = true
    model.goBack()
    model.goBack()
    XCTAssertEqual(model.route, .container("abc123"))
    XCTAssertNil(model.details)
    XCTAssertNil(model.logError)
    XCTAssertTrue(model.logs.isEmpty)
    XCTAssertFalse(model.logsPaused)
  }
  func testMutationRefreshesDiagnosisForTheSameContainer() async throws {
    let model = Dashboard(
      backend: backend(), readSnapshot: { try self.snapshot(running: false) },
      readDetails: { try self.detail($0, exitCode: 137) })
    model.openContainer("abc123")
    model.details = try detail("abc123")
    await model.perform(
      PendingAction(
        title: "Stop", message: "", verb: "stop", containers: [try snapshot().containers[0]],
        vm: false))
    XCTAssertEqual(model.details?.state.exitCode, 137)
    XCTAssertNotNil(model.detailsDate)
    XCTAssertEqual(model.containers.first?.running, false)
  }
  func testUnexpectedExitAlertsButAStopFromTheAppDoesNot() async throws {
    let vm = #"{"name":"default","status":"Running","cpus":10,"memory":21474836480}"#
    func state(_ postgres: String, _ web: String) throws -> Snapshot {
      try Snapshot.decode(
        vm: vm,
        containers: """
          {"ID":"abc123","Names":"demo-postgres-1","Image":"postgres:18",\(postgres),"Ports":"","Labels":"com.docker.compose.project=demo"}
          {"ID":"def456","Names":"other-web-1","Image":"web:latest",\(web),"Ports":"","Labels":"com.docker.compose.project=other"}
          """, stats: "")
    }
    let up = #""State":"running","Status":"Up 1 hour""#
    let crashed = #""State":"exited","Status":"Exited (1) 1 second ago""#
    let killed = #""State":"exited","Status":"Exited (137) 1 second ago""#
    var responses = [try state(up, up), try state(crashed, up), try state(crashed, killed)]
    let model = Dashboard(backend: backend(), readSnapshot: { responses.removeFirst() })
    model.notificationsEnabled = true
    var received: [ContainerAlert] = []
    model.onAlerts = { received += $0 }

    await model.refresh()
    XCTAssertTrue(received.isEmpty)
    await model.refresh()
    XCTAssertEqual(received.map(\.containerID), ["abc123"])
    await model.perform(
      PendingAction(
        title: "Stop", message: "", verb: "stop", containers: [model.containers[1]], vm: false))
    XCTAssertEqual(received.map(\.containerID), ["abc123"])
    XCTAssertEqual(model.containers.last?.running, false)
  }
  func testProjectLogsReturnToTheProjectWithoutAnotherPagesBuffer() async throws {
    let model = Dashboard(backend: backend())
    model.navigate(.containers, project: "demo")
    model.openContainer("abc123")
    model.logs = "postgres output"
    model.goBack()
    model.openProjectLogs("demo")
    XCTAssertEqual(model.route, .projectLogs("demo"))
    XCTAssertTrue(model.logs.isEmpty)
    model.openContainer("abc123")
    model.logs = "single container output"
    model.goBack()
    XCTAssertEqual(model.route, .projectLogs("demo"))
    XCTAssertTrue(model.logs.isEmpty)
    model.goBack()
    XCTAssertEqual(model.route, .containers)
    XCTAssertEqual(model.project, "demo")
  }
  func testRemovalOffersOnlyStoppedContainersAndLeavesTheRemovedPage() async throws {
    let running = try snapshot()
    let stopped = try snapshot(running: false)
    let gone = try Snapshot.decode(
      vm: #"{"name":"default","status":"Running","cpus":10,"memory":21474836480}"#,
      containers: "", stats: "")
    let model = Dashboard(backend: backend(), readSnapshot: { gone })
    model.snapshot = running
    model.request("rm", containers: [running.containers[0]])
    XCTAssertNil(model.pending, "A running container was offered for removal")

    model.snapshot = stopped
    model.navigate(.containers, project: "demo")
    model.openContainer("abc123")
    model.request("rm", containers: stopped.containers)
    let action = try XCTUnwrap(model.pending)
    XCTAssertEqual(action.containers.map(\.id), ["abc123"])
    XCTAssertEqual(action.label, "Remove")
    await model.perform(action)
    XCTAssertEqual(model.route, .containers)
  }
  func testBulkVolumeRemovalContinuesPastARefusalAndKeepsItVisible() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let docker = directory.appendingPathComponent("docker")
    try Data(
      #"""
      #!/bin/sh
      shift 2
      if [ "$1 $2 $3" = "volume rm busy" ]; then echo "volume is in use" >&2; exit 1; fi
      exit 0
      """#.utf8
    ).write(to: docker)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: docker.path)
    let model = Dashboard(
      backend: Backend(
        toolchain: Toolchain(environment: [
          "COLIMA_MINI_DOCKER": docker.path, "COLIMA_MINI_COLIMA": "/usr/bin/true",
        ])))
    let removed = await model.removeVolumes(["first", "busy", "last"])
    XCTAssertEqual(removed, ["first", "last"])
    let error = try XCTUnwrap(model.volumesError)
    XCTAssertTrue(error.contains("busy"), error)
    XCTAssertFalse(error.contains("first") || error.contains("last"), error)
    XCTAssertFalse(model.busy)
  }
  func testReopeningTheSameContainerKeepsOneBackStep() async throws {
    let model = Dashboard(backend: backend())
    model.navigate(.volumes)
    model.openContainer("abc123")
    model.openContainer("abc123", tab: .logs)
    XCTAssertEqual(model.containerTab, .logs)
    model.goBack()
    XCTAssertEqual(model.route, .volumes)
  }
  func testPageCancellationDoesNotLoseSharedVolumeInventory() async throws {
    let gate = ResultGate<[Volume]>()
    let model = Dashboard(backend: backend(), readVolumes: { try await gate.read() })
    model.navigate(.volumes)
    let listRead = Task { await model.loadVolumes() }
    await gate.waitForReaders(1)
    listRead.cancel()
    model.openContainer("abc123")
    model.openVolume("demo_db")
    await model.loadVolumes()
    let volumes = try JSONDecoder().decode(
      [Volume].self,
      from: Data(
        #"[{"name":"demo_db","driver":"local","references":[],"referencesAvailable":true}]"#.utf8))
    await gate.finish(0, with: volumes)
    await listRead.value
    XCTAssertEqual(model.route, .volume("demo_db"))
    XCTAssertEqual(model.volumes.first?.name, "demo_db")
    XCTAssertNotNil(model.volumesDate)
    XCTAssertFalse(model.volumesLoading)
  }

}
