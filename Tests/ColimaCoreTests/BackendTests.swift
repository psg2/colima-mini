import Foundation
import XCTest

@testable import ColimaCore

final class BackendTests: XCTestCase {
  // Real subprocesses provide a small local runtime. Assertions inspect the
  // resulting VM/container state rather than the order of implementation calls.
  func runtime(_ body: (Backend, URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "colima-backend-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = directory.appendingPathComponent("colima.yaml")
    try Data("cpu: 2\nmemory: 2\ndisk: 100\nautoActivate: true\n".utf8).write(to: config)
    let fixture = try SnapshotTests().fixture()
    let state = directory.appendingPathComponent("state.json")
    let object: [String: Any] = [
      "vm": fixture.vm, "containers": fixture.containers, "stats": fixture.stats,
    ]
    try JSONSerialization.data(withJSONObject: object).write(to: state)
    let program = #"""
      #!/usr/bin/env python3
      import json, os, pathlib, re, sys, time
      path = pathlib.Path(os.environ['COLIMA_TEST_STATE'])
      data = json.loads(path.read_text())
      rows = [json.loads(line) for line in data['containers'].splitlines() if line.strip()]
      args = sys.argv[1:]
      if 'DOCKER_HOST' in os.environ:
          sys.exit('foreign Docker host leaked into runtime')
      if pathlib.Path(sys.argv[0]).name == 'colima':
          vm = json.loads(data['vm'])
          if args[0] == 'list':
              print(data['vm'])
          elif args[0] == 'stop':
              vm['status'] = 'Stopped'
              for row in rows:
                  row['State'], row['Status'] = 'exited', 'Exited (0) just now'
          elif args[0] == 'start':
              config = pathlib.Path(os.environ['COLIMA_TEST_CONFIG']).read_text()
              vm.update(status='Running', cpus=int(re.search(r'^cpu: ([0-9]+)', config, re.M)[1]),
                        memory=int(float(re.search(r'^memory: ([0-9.]+)', config, re.M)[1]) * 2**30),
                        disk=int(re.search(r'^disk: ([0-9]+)', config, re.M)[1]) * 2**30)
              rows = [row for row in rows if row['ID'] != data.get('remove_on_start')]
          else:
              sys.exit('unsupported VM operation')
          data['vm'] = json.dumps(vm)
      else:
          if args[:2] != ['--context', 'colima']:
              sys.exit('wrong Docker context')
          args = args[2:]
          if args[0] == 'ps':
              print(data['containers'])
          elif args[0] == 'stats':
              if data.get('fail_stats'): sys.exit('synthetic metrics failure')
              print(data['stats'])
          elif args[0] == 'start':
              for row in rows:
                  if row['ID'] in args[1:] and row['ID'] != data.get('fail_restore'):
                      row['State'], row['Status'] = 'running', 'Up just now'
          elif args[0] == 'logs':
              if args[-1] == 'split':
                  sys.stdout.write('2026-10-02T12:00:02Z hel'); sys.stdout.flush()
                  time.sleep(0.2)
                  print('lo from split', flush=True)
                  sys.exit(0)
              if args[-1] == 'endless':
                  path.with_name('follower.pid').write_text(str(os.getpid()))
                  print('2026-10-02T12:00:00Z first line', flush=True)
                  time.sleep(60)
              print('2026-10-02T12:00:00Z stdout log', flush=True)
              print('2026-10-02T12:00:01Z stderr log', file=sys.stderr, flush=True)
              print('2026-10-02T12:00:01Z equal timestamp\nmultiline body', flush=True)
          else:
              sys.exit('unsupported container operation')
      data['containers'] = '\n'.join(json.dumps(row) for row in rows)
      if args[0] in ('start', 'stop'):
          path.write_text(json.dumps(data))
      """#
    for name in ["docker", "colima"] {
      let url = directory.appendingPathComponent(name)
      try Data(program.utf8).write(to: url)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    var environment = ProcessInfo.processInfo.environment
    environment["COLIMA_MINI_DOCKER"] = directory.appendingPathComponent("docker").path
    environment["COLIMA_MINI_COLIMA"] = directory.appendingPathComponent("colima").path
    environment["PATH"] = directory.path + ":" + (environment["PATH"] ?? "")
    environment["DOCKER_HOST"] = "unix:///nonexistent/foreign.sock"
    environment["DOCKER_CONTEXT"] = "foreign"
    environment["COLIMA_TEST_STATE"] = state.path
    environment["COLIMA_TEST_CONFIG"] = config.path
    let backend = Backend(toolchain: Toolchain(environment: environment), configurationURL: config)
    try await body(backend, config)
  }
  func testSnapshotUsesColimaDespiteForeignEnvironment() async throws {
    try await runtime { backend, _ in
      let snapshot = try await backend.snapshot()
      XCTAssertEqual(snapshot.containers.count, 3)
      XCTAssertEqual(snapshot.vm.status, "Running")
    }
  }
  func testResourceRestartRestoresOnlyPreviouslyRunningContainers() async throws {
    try await runtime { backend, config in
      let before = try await backend.snapshot()
      let desired = ResourceSettings(cpus: 1, memoryGiB: 2.5, diskGiB: 120)
      try await backend.apply(desired, restart: true)
      let after = try await backend.snapshot()
      XCTAssertEqual(after.vm.cpus, 1)
      XCTAssertEqual(after.vm.disk, 120 << 30)
      XCTAssertEqual(after.vm.memory, Int64(2.5 * 1_073_741_824))
      XCTAssertEqual(
        Set(after.containers.filter(\.running).map(\.id)),
        Set(before.containers.filter(\.running).map(\.id)))
      XCTAssertTrue(try String(contentsOf: config, encoding: .utf8).contains("autoActivate: true"))
    }
  }
  func testSaveForNextStartLeavesRunningAllocationUntouched() async throws {
    try await runtime { backend, _ in
      let before = try await backend.snapshot()
      let desired = ResourceSettings(cpus: 1, memoryGiB: 2, diskGiB: 100)
      try await backend.apply(desired, restart: false)
      let after = try await backend.snapshot()
      XCTAssertEqual(try backend.settings(), desired)
      XCTAssertEqual(after.vm.cpus, before.vm.cpus)
      XCTAssertEqual(
        after.containers.filter(\.running).map(\.id), before.containers.filter(\.running).map(\.id))
    }
  }
  func testContainerLogsIncludeBothStreams() async throws {
    try await runtime { backend, _ in
      var logs = ""
      for try await chunk in backend.followLogs("sample") { logs += chunk }
      XCTAssertTrue(logs.contains("stdout log"))
      XCTAssertTrue(logs.contains("stderr log"))
      XCTAssertEqual(
        logs,
        "2026-10-02T12:00:00Z stdout log\n2026-10-02T12:00:01Z stderr log\n2026-10-02T12:00:01Z equal timestamp\nmultiline body\n"
      )
    }
  }
  func testProjectLogsLabelWholeLinesFromEverySource() async throws {
    try await runtime { backend, _ in
      var text = ""
      for try await chunk in backend.followProjectLogs([
        LogSource(id: "sample", label: "db"), LogSource(id: "split", label: "web"),
      ]) { text += chunk }
      let lines = text.split(separator: "\n").map(String.init)
      XCTAssertTrue(lines.contains("2026-10-02T12:00:02Z [web] hello from split"))
      XCTAssertTrue(lines.contains("2026-10-02T12:00:00Z [db] stdout log"))
      XCTAssertTrue(lines.contains("2026-10-02T12:00:01Z [db] stderr log"))
      // A continuation line without a timestamp still names its source.
      XCTAssertTrue(lines.contains("[db] multiline body"))
      XCTAssertEqual(lines.count, 5)
    }
  }
  func testStoppingAFollowTerminatesTheLogProcess() async throws {
    try await runtime { backend, config in
      var stream = backend.followLogs("endless").makeAsyncIterator()
      let first = try await stream.next()
      XCTAssertEqual(first, "2026-10-02T12:00:00Z first line\n")
      let pidFile = config.deletingLastPathComponent().appendingPathComponent("follower.pid")
      let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8)))
      stream = backend.followLogs("sample").makeAsyncIterator()
      let deadline = Date().addingTimeInterval(4)
      while kill(pid, 0) == 0 && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
      XCTAssertNotEqual(kill(pid, 0), 0, "The follower outlived its stream")
    }
  }
  func testResourceRestartCapturesExternallyChangedRunningSet() async throws {
    try await runtime { backend, config in
      let state = config.deletingLastPathComponent().appendingPathComponent("state.json")
      var object = try JSONSerialization.jsonObject(with: Data(contentsOf: state)) as! [String: Any]
      let rows = try Snapshot.lines(object["containers"] as! String, as: Container.self)
      let previouslyStopped = try XCTUnwrap(rows.first { !$0.running })
      let encoded = try (object["containers"] as! String).split(separator: "\n").map {
        original -> [String: Any] in
        var value = try JSONSerialization.jsonObject(with: Data(original.utf8)) as! [String: Any]
        value["State"] = value["ID"] as? String == previouslyStopped.id ? "running" : "exited"
        value["Status"] =
          value["ID"] as? String == previouslyStopped.id ? "Up just now" : "Exited (0) just now"
        return value
      }
      object["containers"] = try encoded.map {
        String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self)
      }.joined(separator: "\n")
      try JSONSerialization.data(withJSONObject: object).write(to: state)
      try await backend.apply(ResourceSettings(cpus: 1, memoryGiB: 2), restart: true)
      let after = try await backend.snapshot()
      XCTAssertEqual(Set(after.containers.filter(\.running).map(\.id)), [previouslyStopped.id])
    }
  }
  func testResourceRestartReportsMissingOrUnrestoredContainers() async throws {
    for failure in ["remove_on_start", "fail_restore"] {
      try await runtime { backend, config in
        let before = try await backend.snapshot()
        let running = try XCTUnwrap(before.containers.first { $0.running })
        let state = config.deletingLastPathComponent().appendingPathComponent("state.json")
        var object =
          try JSONSerialization.jsonObject(with: Data(contentsOf: state)) as! [String: Any]
        object[failure] = running.id
        try JSONSerialization.data(withJSONObject: object).write(to: state)
        do {
          try await backend.apply(
            ResourceSettings(cpus: 1, memoryGiB: 2), restart: true)
          XCTFail("Partial restoration was accepted")
        } catch {
          XCTAssertTrue(error.localizedDescription.contains("restoration is incomplete"))
        }
        let after = try await backend.snapshot()
        XCTAssertEqual(after.vm.cpus, 1)
        XCTAssertFalse(after.containers.contains { $0.id == running.id && $0.running })
      }
    }
  }
  func testResourceRestartDoesNotDependOnMetricsAvailability() async throws {
    try await runtime { backend, config in
      let before = try await backend.snapshot()
      let state = config.deletingLastPathComponent().appendingPathComponent("state.json")
      var object = try JSONSerialization.jsonObject(with: Data(contentsOf: state)) as! [String: Any]
      object["fail_stats"] = true
      try JSONSerialization.data(withJSONObject: object).write(to: state)
      try await backend.apply(
        ResourceSettings(cpus: 1, memoryGiB: 2), restart: true)
      let restored =
        try JSONSerialization.jsonObject(with: Data(contentsOf: state)) as! [String: Any]
      let after = try Snapshot.decode(
        vm: restored["vm"] as! String, containers: restored["containers"] as! String, stats: "")
      XCTAssertEqual(after.vm.cpus, 1)
      XCTAssertEqual(
        Set(after.containers.filter(\.running).map(\.id)),
        Set(before.containers.filter(\.running).map(\.id)))
    }
  }
}
