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
    let gate = ResultGate<String>()
    let model = Dashboard(backend: backend(), readLogs: { _ in try await gate.read() })
    model.openContainer("abc123")
    let oldLogs = Task { await model.loadLogs("abc123") }
    await gate.waitForReaders(1)
    model.openContainer("def456")
    let newLogs = Task { await model.loadLogs("def456") }
    await gate.waitForReaders(2)
    await gate.finish(1, with: "current container log")
    await newLogs.value
    await gate.finish(0, with: "old container log")
    await oldLogs.value
    XCTAssertEqual(model.logs, "current container log")
    XCTAssertFalse(model.logsLoading)
  }
  func testBackRestoresProjectSearchCollapseAndScrollContext() throws {
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
  func testGroupControlHandlesMixedGroupsAndSearchWithoutErasingPreferences() throws {
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
      backend: backend(), readLogs: { _ in throw AppError.message("Daemon unavailable") })
    model.openContainer("abc123")
    model.logs = "last good log"
    await model.loadLogs("abc123")
    XCTAssertEqual(model.logs, "last good log")
    XCTAssertEqual(model.logError, "Daemon unavailable")
    model.logsPaused = true
    await model.loadLogs("abc123")
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
  func testBackToEarlierContainerClearsOtherDetailsAndPausedLogs() throws {
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
