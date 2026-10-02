import Foundation
import XCTest

@testable import ColimaCore

final class SnapshotTests: XCTestCase {
  func fixture() throws -> Fixture {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: "sample", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
  }
  func testComposeGroupingMetricsAndPortDeduplication() throws {
    let snapshot = try fixture().snapshot
    XCTAssertEqual(snapshot.projects, ["Standalone", "demo"])
    XCTAssertEqual(snapshot.containers.count, 3)
    XCTAssertEqual(snapshot.containers.filter(\.running).count, 2)
    XCTAssertEqual(
      snapshot.containers.flatMap(\.endpoints).compactMap(\.port).sorted(), [5432, 8080])
    XCTAssertEqual(snapshot.totalCPU(snapshot.containers), 1.55, accuracy: 0.001)
    XCTAssertEqual(snapshot.totalMemory(snapshot.containers), 172 * 1_048_576)
  }
  func testDifferentProfileCannotReplaceDefault() throws {
    let sample = try fixture()
    let extra = #"{"name":"sandbox","status":"Stopped","cpus":1,"memory":1073741824}"#
    let snapshot = try Snapshot.decode(
      vm: extra + "\n" + sample.vm, containers: sample.containers, stats: sample.stats)
    XCTAssertEqual(snapshot.vm.cpus, 10)
  }
  func testStoppedVMClearsStaleContainersAndMetrics() throws {
    let sample = try fixture()
    let stopped = sample.vm.replacingOccurrences(of: "Running", with: "Stopped")
    let snapshot = try Snapshot.decode(
      vm: stopped, containers: sample.containers, stats: sample.stats)
    XCTAssertTrue(snapshot.containers.isEmpty)
    XCTAssertTrue(snapshot.usage.isEmpty)
  }
  func testMalformedContainersAndMissingProfileFail() throws {
    let sample = try fixture()
    XCTAssertThrowsError(
      try Snapshot.decode(vm: sample.vm, containers: "invalid JSON", stats: sample.stats))
    XCTAssertThrowsError(
      try Snapshot.decode(vm: "", containers: sample.containers, stats: sample.stats))
  }
  func testDecimalMemoryAndMulticoreCPU() {
    let usage = Usage(
      id: "x", cpuPercent: "200.00%", memoryUsage: "1.5GB / 20GB", memoryPercent: "7.5%")
    XCTAssertEqual(usage.memoryBytes, 1_500_000_000)
    XCTAssertEqual(usage.cpu, 200)
  }
  func testSampleModeRejectsRuntimeChanges() async throws {
    let backend = Backend(fixture: try fixture())
    do {
      _ = try await backend.vm("stop")
      XCTFail("Sample VM was mutated")
    } catch {}
    do {
      _ = try await backend.docker(["stop", "sample"])
      XCTFail("Sample container was mutated")
    } catch {}
    do {
      try await backend.apply(
        ResourceSettings(cpus: 2, memoryGiB: 2), restart: false, snapshot: backend.snapshot())
      XCTFail("Sample resources were saved")
    } catch {}
  }
}
