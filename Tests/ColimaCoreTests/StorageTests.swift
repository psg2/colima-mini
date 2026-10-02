import Foundation
import XCTest

@testable import ColimaCore

final class StorageTests: XCTestCase {
  func testDiskMeasurementsDistinguishDecimalBinaryAndUnknown() {
    XCTAssertEqual(DiskBytes.parse("1.976GB"), 1_976_000_000)
    XCTAssertEqual(DiskBytes.parse("1.5GiB"), 1_610_612_736)
    XCTAssertEqual(DiskBytes.parse("93.01MB (41%)"), 93_010_000)
    XCTAssertEqual(DiskBytes.parse("0B"), 0)
    XCTAssertNil(DiskBytes.parse("Unknown"))
    XCTAssertNil(DiskBytes.parse("-1GB"))
    XCTAssertNil(DiskBytes.parse("NaNGB"))
  }

  func testDataFilesystemReservedSpaceIsNotCalledUsed() throws {
    let fs = try FilesystemUsage.decode(
      "Filesystem 1B-blocks Used Available Use% Mounted on\n/dev/vdb1 1000 100 800 10% /var/lib/docker\n"
    )
    XCTAssertEqual(fs.sizeBytes, 1000)
    XCTAssertEqual(fs.usedBytes, 100)
    XCTAssertEqual(fs.availableBytes, 800)
    XCTAssertEqual(fs.reservedBytes, 100)
    XCTAssertEqual(fs.mountpoint, "/var/lib/docker")
    XCTAssertThrowsError(try FilesystemUsage.decode("Filesystem\n/dev/vdb1 1000 1000 800 10% /"))
    XCTAssertThrowsError(try FilesystemUsage.decode("Filesystem\n/dev/vdb1 unknown 100 800 10% /"))
  }

  func testUnsupportedAccountingFailsInsteadOfInventingZeros() throws {
    XCTAssertThrowsError(try DockerStorageCategory.decode(""))
    XCTAssertThrowsError(
      try DockerStorageCategory.decode(
        #"{"Type":"Images","Size":"N/A","Reclaimable":"0B","TotalCount":"1","Active":"0"}"#))
    let rows = try DockerStorageCategory.decode(
      #"{"Type":"Images","Size":"1.976GB","Reclaimable":"100MB (5%)","TotalCount":"3","Active":"2"}"#
    )
    XCTAssertEqual(rows.first?.sizeBytes, 1_976_000_000)
    XCTAssertEqual(rows.first?.reclaimableBytes, 100_000_000)
  }

  func testMissingOptionalFixtureInventoryAndDiskRemainCompatible() throws {
    let fixture = try JSONDecoder().decode(
      Fixture.self,
      from: Data(
        #"{"vm":"{\"name\":\"default\",\"status\":\"Stopped\",\"cpus\":2,\"memory\":2147483648}","containers":"","stats":""}"#
          .utf8))
    XCTAssertNil(try fixture.snapshot.vm.disk)
    XCTAssertNil(fixture.details)
    XCTAssertNil(fixture.volumes)
    XCTAssertNil(fixture.storage)
  }

  func testStorageSectionsFailIndependently() async throws {
    try await InspectionRuntime.run(overrides: ["filesystemError": true]) { backend in
      let storage = try await backend.storage()
      XCTAssertEqual(storage.configuredCapacityBytes, 107_374_182_400)
      XCTAssertNil(storage.filesystem)
      XCTAssertNotNil(storage.errors["filesystem"])
      XCTAssertEqual(storage.docker.first?.sizeBytes, 1_976_000_000)
      XCTAssertNil(storage.errors["docker"])
      XCTAssertNil(storage.hostAllocatedBytes)
      XCTAssertNotNil(storage.errors["host"])
    }
    try await InspectionRuntime.run(overrides: ["dockerError": true]) { backend in
      let storage = try await backend.storage()
      XCTAssertEqual(storage.filesystem?.usedBytes, 20_000_000_000)
      XCTAssertTrue(storage.docker.isEmpty)
      XCTAssertNotNil(storage.errors["docker"])
    }
  }

  func testUnsupportedDataRootIsUnavailableRatherThanPassedToSSH() async throws {
    try await InspectionRuntime.run(overrides: ["dataRoot": "/srv/docker data; invalid"]) {
      backend in
      let storage = try await backend.storage()
      XCTAssertNil(storage.filesystem)
      XCTAssertTrue(storage.errors["filesystem"]?.contains("usable data filesystem path") == true)
      XCTAssertFalse(storage.docker.isEmpty)
    }
  }

  func testCustomDockerDataRootMeasuresItsOwnFilesystem() async throws {
    try await InspectionRuntime.run(overrides: [
      "dataRoot": "/srv/docker-data",
      "filesystem":
        "Filesystem 1B-blocks Used Available Use% Mounted on\n/dev/vdc1 1000 100 800 10% /srv/docker-data\n",
    ]) { backend in
      let storage = try await backend.storage()
      XCTAssertEqual(storage.filesystem?.mountpoint, "/srv/docker-data")
      XCTAssertEqual(storage.filesystem?.usedBytes, 100)
      XCTAssertNil(storage.errors["filesystem"])
    }
  }

  func testStoppedVMReportsCapacityAndUnavailableRuntimeMeasurements() async throws {
    try await InspectionRuntime.run(overrides: [
      "vm":
        #"{"name":"default","status":"Stopped","cpus":10,"memory":21474836480,"disk":107374182400}"#
    ]) { backend in
      let storage = try await backend.storage()
      XCTAssertEqual(storage.configuredCapacityBytes, 107_374_182_400)
      XCTAssertNil(storage.filesystem)
      XCTAssertTrue(storage.docker.isEmpty)
      XCTAssertTrue(storage.errors["docker"]?.contains("Start Colima") == true)
    }
  }

  func testSparseImagesMeasureAllocationAndUnsupportedLayoutsStayUnknown() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(
      "colima-sparse-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let lima = home.appendingPathComponent("_lima")
    try FileManager.default.createDirectory(
      at: lima.appendingPathComponent("colima"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: lima.appendingPathComponent("_disks/colima"), withIntermediateDirectories: true)
    let config = lima.appendingPathComponent("colima/lima.yaml")
    try Data("vmType: vz\nadditionalDisks:\n    - name: colima\n      format: false\n".utf8).write(
      to: config)
    for path in ["colima/disk", "_disks/colima/datadisk"] {
      let url = lima.appendingPathComponent(path)
      FileManager.default.createFile(atPath: url.path, contents: nil)
      let file = try FileHandle(forWritingTo: url)
      try file.truncate(atOffset: 1_073_741_824)
      try file.write(contentsOf: Data("sample".utf8))
      try file.close()
    }
    let allocation = try HostDiskFootprint.allocatedBytes(home: home)
    XCTAssertGreaterThan(allocation, 0)
    XCTAssertLessThan(allocation, 2_147_483_648)
    try Data("vmType: qemu\n".utf8).write(to: config)
    XCTAssertThrowsError(try HostDiskFootprint.allocatedBytes(home: home))
  }
}
