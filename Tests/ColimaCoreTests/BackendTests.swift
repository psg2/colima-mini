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
      import json, os, pathlib, re, sys
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
                        memory=int(float(re.search(r'^memory: ([0-9.]+)', config, re.M)[1]) * 2**30))
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
              print(data['stats'])
          elif args[0] == 'start':
              for row in rows:
                  if row['ID'] in args[1:]: row['State'], row['Status'] = 'running', 'Up just now'
          elif args[0] == 'logs':
              print('stdout log')
              print('stderr log', file=sys.stderr)
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
      let desired = ResourceSettings(cpus: 1, memoryGiB: 2.5)
      try await backend.apply(desired, restart: true, snapshot: before)
      let after = try await backend.snapshot()
      XCTAssertEqual(after.vm.cpus, 1)
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
      let desired = ResourceSettings(cpus: 1, memoryGiB: 2)
      try await backend.apply(desired, restart: false, snapshot: before)
      let after = try await backend.snapshot()
      XCTAssertEqual(try backend.settings(), desired)
      XCTAssertEqual(after.vm.cpus, before.vm.cpus)
      XCTAssertEqual(
        after.containers.filter(\.running).map(\.id), before.containers.filter(\.running).map(\.id))
    }
  }
  func testContainerLogsIncludeBothStreams() async throws {
    try await runtime { backend, _ in
      let logs = try await backend.logs("sample")
      XCTAssertTrue(logs.contains("stdout log"))
      XCTAssertTrue(logs.contains("stderr log"))
    }
  }
}
