import Foundation
import XCTest

@testable import ColimaCore

final class InspectionTests: XCTestCase {
  func testDetailsKeepDatabaseProtocolAndSeparateNamedAndBindMounts() throws {
    let rows = try ContainerDetails.decode(InspectionRuntime.inspections)
    let database = try XCTUnwrap(rows.first { $0.id == "database" })
    XCTAssertEqual(database.state.health, "healthy")
    XCTAssertEqual(database.ports.first?.address, "127.0.0.1:5432")
    XCTAssertEqual(database.ports.first?.protocolName, "tcp")
    XCTAssertEqual(database.mounts.first?.name, "demo_db")
    XCTAssertEqual(database.mounts.first?.type, "volume")
    let worker = try XCTUnwrap(rows.first { $0.id == "worker" })
    XCTAssertEqual(worker.state.oomKilled, true)
    XCTAssertEqual(worker.state.exitCode, 137)
    XCTAssertNil(worker.state.health)
    XCTAssertNil(worker.project)
    XCTAssertTrue(worker.mounts[0].readOnly)
    XCTAssertEqual(rows.first { $0.id == "web" }?.mounts.first?.type, "bind")
  }

  func testMissingHealthAndMountMetadataRemainUnavailable() throws {
    let row = try XCTUnwrap(
      ContainerDetails.decode(
        #"{"Id":"missing","Name":"/missing","Image":"sha256:unknown","Config":{"Image":"alpine","Labels":null},"State":{"Status":"created"}}"#
      ).first)
    XCTAssertNil(row.state.oomKilled)
    XCTAssertNil(row.state.running)
    XCTAssertNil(row.state.health)
    XCTAssertEqual(row.mountsAvailable, false)
    XCTAssertThrowsError(try ContainerDetails.decode("unsupported inspection"))
  }

  func testImagesLinkContainersWithFullAndUnambiguousShortIDs() throws {
    let details = try ContainerDetails.decode(InspectionRuntime.inspections)
    let fullID = "sha256:" + String(repeating: "a", count: 64)
    XCTAssertEqual(
      DockerImage.referencingContainers(
        imageID: fullID, containers: details, knownImageIDs: [fullID]),
      ["database", "worker"])
    XCTAssertEqual(
      DockerImage.referencingContainers(
        imageID: String(repeating: "a", count: 12), containers: details, knownImageIDs: [fullID]),
      ["database", "worker"])
    let collision =
      "sha256:" + String(repeating: "a", count: 12) + String(repeating: "b", count: 52)
    XCTAssertNil(
      DockerImage.referencingContainers(
        imageID: String(repeating: "a", count: 12), containers: details,
        knownImageIDs: [fullID, collision]))
  }

  func testSampleReadsDoNotRequireExecutables() async throws {
    let fixture = try SnapshotTests().fixture()
    let backend = Backend(
      fixture: fixture,
      toolchain: Toolchain(environment: [
        "COLIMA_MINI_DOCKER": "/nonexistent/docker", "COLIMA_MINI_COLIMA": "/nonexistent/colima",
      ]))
    let id = try XCTUnwrap(fixture.details?.keys.first)
    let details = try await backend.details(id)
    XCTAssertEqual(details.id, id)
    let volumes = try await backend.volumes()
    let images = try await backend.images()
    let storage = try await backend.storage()
    XCTAssertEqual(volumes.count, 3)
    XCTAssertEqual(images.count, 3)
    XCTAssertNotNil(storage.filesystem)
    do {
      _ = try await backend.details("removed")
      XCTFail("Removed sample has stale details")
    } catch { XCTAssertTrue(error.localizedDescription.contains("sample")) }
  }

  func testBackendReferencesIncludeStoppedContainersAndUnknownMeasurements() async throws {
    try await InspectionRuntime.run { backend in
      let volumes = try await backend.volumes()
      let database = try XCTUnwrap(volumes.first { $0.name == "demo_db" })
      XCTAssertEqual(database.references.map(\.containerID), ["database", "worker"])
      XCTAssertEqual(database.references.first { $0.containerID == "worker" }?.running, false)
      XCTAssertEqual(database.attached, true)
      XCTAssertEqual(database.sizeBytes, 1_976_000_000)
      let plugin = try XCTUnwrap(volumes.first { $0.name == "plugin_data" })
      XCTAssertNil(plugin.sizeBytes)
      XCTAssertEqual(plugin.attached, false)
      let details = try await backend.details("worker")
      XCTAssertEqual(details.state.oomKilled, true)
      let images = try await backend.images()
      XCTAssertEqual(images.first?.containerIDs, ["database", "worker"])
      XCTAssertEqual(images.first?.sharedBytes, 100_000_000)
      XCTAssertEqual(images.first?.uniqueBytes, 1_876_000_000)
    }
  }

  func testAnonymousVolumesAreIdentifiedByDockerLabel() async throws {
    let anonymous = String(repeating: "c", count: 64)
    try await InspectionRuntime.run(overrides: [
      "volumeList":
        "{\"Name\":\"demo_db\",\"Driver\":\"local\"}\n{\"Name\":\"\(anonymous)\",\"Driver\":\"local\"}",
      "volumeMetadata":
        "{\"Name\":\"demo_db\",\"Driver\":\"local\",\"Labels\":{\"com.docker.compose.project\":\"demo\"}}\n{\"Name\":\"\(anonymous)\",\"Driver\":\"local\",\"Labels\":{\"com.docker.volume.anonymous\":\"\"}}",
    ]) { backend in
      let volumes = try await backend.volumes()
      XCTAssertEqual(volumes.first { $0.name == anonymous }?.anonymous, true)
      XCTAssertEqual(volumes.first { $0.name == "demo_db" }?.anonymous, false)
      XCTAssertEqual(volumes.first { $0.name == "demo_db" }?.project, "demo")
    }
  }

  func testFailedReferenceReadNeverReportsVolumesAsUnattached() async throws {
    try await InspectionRuntime.run(overrides: ["inspectError": true]) { backend in
      let volumes = try await backend.volumes()
      XCTAssertTrue(volumes.allSatisfy { !$0.referencesAvailable && $0.attached == nil })
      XCTAssertTrue(volumes.allSatisfy { $0.dataIssue?.contains("reference") == true })
      XCTAssertEqual(volumes.first { $0.name == "demo_db" }?.sizeBytes, 1_976_000_000)
    }
  }
}

enum InspectionRuntime {
  static let inspections = """
    {"Id":"database","Name":"/demo-postgres-1","Image":"sha256:\(String(repeating: "a", count: 64))","Config":{"Image":"postgres:17","Labels":{"com.docker.compose.project":"demo","com.docker.compose.service":"postgres"}},"State":{"Status":"running","Running":true,"ExitCode":0,"OOMKilled":false,"Health":{"Status":"healthy"}},"RestartCount":0,"Mounts":[{"Type":"volume","Name":"demo_db","Source":"/var/lib/docker/volumes/demo_db/_data","Destination":"/var/lib/postgresql/data","RW":true}],"NetworkSettings":{"Ports":{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"5432"}],"80/tcp":null}}}
    {"Id":"worker","Name":"/worker","Image":"sha256:\(String(repeating: "a", count: 64))","Config":{"Image":"postgres:17","Labels":{"com.docker.compose.project":null}},"State":{"Status":"exited","Running":false,"ExitCode":137,"OOMKilled":true},"Mounts":[{"Type":"volume","Name":"demo_db","Source":"/var/lib/docker/volumes/demo_db/_data","Destination":"/backup/source","RW":false}]}
    {"Id":"web","Name":"/web","Image":"sha256:\(String(repeating: "b", count: 64))","Config":{"Image":"nginx:alpine"},"State":{"Status":"running","Running":true},"Mounts":[{"Type":"bind","Name":"demo_db","Source":"/tmp/demo_db","Destination":"/data","RW":true}]}
    """
  static func run(
    overrides: [String: Any] = [:], body: (Backend) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "colima-inspection-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var state: [String: Any] = [
      "vm":
        #"{"name":"default","status":"Running","cpus":10,"memory":21474836480,"disk":107374182400}"#,
      "inspections": inspections,
      "dataRoot": "/var/lib/docker",
      "volumeList":
        "{\"Name\":\"demo_db\",\"Driver\":\"local\"}\n{\"Name\":\"plugin_data\",\"Driver\":\"plugin\"}",
      "volumeMetadata":
        "{\"Name\":\"demo_db\",\"Driver\":\"local\",\"Labels\":{\"com.docker.compose.project\":\"demo\"}}\n{\"Name\":\"plugin_data\",\"Driver\":\"plugin\",\"Labels\":null}",
      "verbose":
        "{\"Images\":[{\"ID\":\"sha256:\(String(repeating: "a", count: 64))\",\"Repository\":\"postgres\",\"Tag\":\"17\",\"Size\":\"1.976GB\",\"SharedSize\":\"100MB\",\"UniqueSize\":\"1.876GB\"}],\"Volumes\":[{\"Name\":\"demo_db\",\"Size\":\"1.976GB\"},{\"Name\":\"plugin_data\",\"Size\":\"N/A\"}]}",
      "summary":
        #"{"Type":"Images","TotalCount":"1","Active":"1","Size":"1.976GB","Reclaimable":"100MB (5%)"}"#,
      "filesystem":
        "Filesystem 1B-blocks Used Available Use% Mounted on\n/dev/vdb1 100000000000 20000000000 75000000000 20% /var/lib/docker\n",
    ]
    state.merge(overrides, uniquingKeysWith: { _, new in new })
    let stateURL = directory.appendingPathComponent("state.json")
    try JSONSerialization.data(withJSONObject: state).write(to: stateURL)
    let program = #"""
      #!/usr/bin/env python3
      import json, os, pathlib, sys
      d = json.loads(pathlib.Path(os.environ['COLIMA_INSPECTION_STATE']).read_text())
      a = sys.argv[1:]
      if pathlib.Path(sys.argv[0]).name == 'colima':
          if a[0] == 'list': print(d['vm'])
          elif a[0] == 'ssh':
              if d.get('filesystemError') or a[-1] != d['dataRoot']: sys.exit('data filesystem unavailable')
              print(d['filesystem'])
          else: sys.exit('unsupported Colima read')
      else:
          if a[:2] != ['--context', 'colima'] or 'DOCKER_HOST' in os.environ:
              sys.exit('foreign Docker runtime')
          a = a[2:]
          if a[0] == 'info': print(d['dataRoot'])
          elif a[0] == 'ps':
              print('\n'.join(json.loads(l)['Id'] for l in d['inspections'].splitlines()))
          elif a[0] == 'inspect':
              if d.get('inspectError'): sys.exit('container references unavailable')
              for line in d['inspections'].splitlines():
                  if json.loads(line)['Id'] in a: print(line)
          elif a[:2] == ['volume', 'ls']: print(d['volumeList'])
          elif a[:2] == ['volume', 'inspect']: print(d['volumeMetadata'])
          elif a[:2] == ['system', 'df']:
              if d.get('dockerError'): sys.exit('daemon accounting unavailable')
              print(d['verbose'] if '--verbose' in a else d['summary'])
          else: sys.exit('unsupported Docker read')
      """#
    for name in ["docker", "colima"] {
      let url = directory.appendingPathComponent(name)
      try Data(program.utf8).write(to: url)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    var env = ProcessInfo.processInfo.environment
    env["COLIMA_MINI_DOCKER"] = directory.appendingPathComponent("docker").path
    env["COLIMA_MINI_COLIMA"] = directory.appendingPathComponent("colima").path
    env["COLIMA_HOME"] = directory.appendingPathComponent("unsupported-home").path
    env["COLIMA_INSPECTION_STATE"] = stateURL.path
    env["DOCKER_HOST"] = "unix:///foreign.sock"
    try await body(Backend(toolchain: Toolchain(environment: env)))
  }
}
