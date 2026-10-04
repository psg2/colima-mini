import Foundation
import Testing

@testable import ColimaCore

struct SnapshotTests {
    func fixture() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "sample", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
    @Test func composeGroupingMetricsAndPortDeduplication() throws {
        let snapshot = try fixture().snapshot
        #expect(snapshot.projects == ["Standalone", "demo"])
        #expect(snapshot.containers.count == 3)
        #expect(snapshot.containers.filter(\.running).count == 2)
        #expect(snapshot.containers.flatMap(\.endpoints).compactMap(\.port).sorted() == [5432, 8080])
        #expect(abs(snapshot.totalCPU(snapshot.containers) - 1.55) <= 0.001)
        #expect(snapshot.totalMemory(snapshot.containers) == 172 * 1_048_576)
    }
    @Test func differentProfileCannotReplaceDefault() throws {
        let sample = try fixture()
        let extra = #"{"name":"sandbox","status":"Stopped","cpus":1,"memory":1073741824}"#
        let snapshot = try Snapshot.decode(
            vm: extra + "\n" + sample.vm, containers: sample.containers, stats: sample.stats)
        #expect(snapshot.vm.cpus == 10)
    }
    @Test func stoppedVMClearsStaleContainersAndMetrics() throws {
        let sample = try fixture()
        let stopped = sample.vm.replacingOccurrences(of: "Running", with: "Stopped")
        let snapshot = try Snapshot.decode(
            vm: stopped, containers: sample.containers, stats: sample.stats)
        #expect(snapshot.containers.isEmpty)
        #expect(snapshot.usage.isEmpty)
    }
    @Test func malformedContainersAndMissingProfileFail() throws {
        let sample = try fixture()
        #expect(throws: (any Error).self) { try Snapshot.decode(vm: sample.vm, containers: "invalid JSON", stats: sample.stats) }
        #expect(throws: (any Error).self) { try Snapshot.decode(vm: "", containers: sample.containers, stats: sample.stats) }
    }
    @Test func decimalMemoryAndMulticoreCPU() {
        let usage = Usage(
            id: "x", cpuPercent: "200.00%", memoryUsage: "1.5GB / 20GB", memoryPercent: "7.5%")
        #expect(usage.memoryBytes == 1_500_000_000)
        #expect(usage.cpu == 200)
    }
    @Test func sampleModeRejectsRuntimeChanges() async throws {
        let backend = Backend(fixture: try fixture())
        do {
            _ = try await backend.vm("stop")
            Issue.record("Sample VM was mutated")
        } catch {}
        do {
            _ = try await backend.docker(["stop", "sample"])
            Issue.record("Sample container was mutated")
        } catch {}
        do {
            try await backend.apply(
                ResourceSettings(cpus: 2, memoryGiB: 2), restart: false)
            Issue.record("Sample resources were saved")
        } catch {}
    }
}
