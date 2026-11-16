import Foundation
import Testing

@testable import ColimaCore

// The PID of a process that has already exited.
func exitedPID() throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try process.run()
    process.waitUntilExit()
    return process.processIdentifier
}

struct OwnershipTests {
    private let vm = #"{"name":"default","status":"Running","cpus":10,"memory":21474836480}"#

    // Leaked test containers used to land in Standalone with no origin.
    @Test func testcontainersSessionsBecomeProjectsWithRyukStatus() throws {
        let snapshot = try Snapshot.decode(
            vm: vm,
            containers: """
                {"ID":"r1","Names":"testcontainers-ryuk-aaaa1111bbbb","Image":"testcontainers/ryuk:0.11.0","State":"running","Status":"Up","Ports":"","Labels":"org.testcontainers=true"}
                {"ID":"a1","Names":"brave_pg","Image":"postgres:18","State":"running","Status":"Up","Ports":"","Labels":"org.testcontainers=true,org.testcontainers.session-id=aaaa1111bbbb"}
                {"ID":"b1","Names":"calm_pg","Image":"postgres:18","State":"running","Status":"Up","Ports":"","Labels":"org.testcontainers=true,org.testcontainers.session-id=cccc2222dddd"}
                {"ID":"s1","Names":"loose","Image":"web","State":"running","Status":"Up","Ports":"","Labels":""}
                """, stats: "")

        #expect(snapshot.projects == ["Standalone", "testcontainers aaaa1111", "testcontainers cccc2222"])
        #expect(snapshot.reapers == ["testcontainers aaaa1111": .alive, "testcontainers cccc2222": .gone])
    }

    @Test func ownerFolderIsTheOriginWhenComposeRecordedNone() throws {
        let snapshot = try Snapshot.decode(
            vm: vm,
            containers: """
                {"ID":"a1","Names":"api","Image":"web","State":"running","Status":"Up","Ports":"","Labels":"dev.owner.working_dir=/Users/dev/.claude-worktrees/wedding/blue-fox,dev.owner.pid=123"}
                {"ID":"b1","Names":"web-1","Image":"web","State":"running","Status":"Up","Ports":"","Labels":"com.docker.compose.project=shop,com.docker.compose.project.working_dir=/srv/shop,dev.owner.working_dir=/elsewhere"}
                """, stats: "")
        let owned = try #require(snapshot.containers.first { $0.name == "api" })
        #expect(owned.origin?.path == "/Users/dev/.claude-worktrees/wedding/blue-fox")
        #expect(owned.project == "Standalone")
        #expect(snapshot.containers.first { $0.name == "web-1" }?.origin?.path == "/srv/shop")
    }

    @Test func ryukIsRecognizedFromItsImageEvenWhenMirrored() {
        #expect(Testcontainers.isRyuk(name: "x", image: "registry.local/testcontainers/ryuk:0.9", labels: [:]))
        #expect(Testcontainers.isRyuk(name: "x", image: "testcontainers/ryuk@sha256:abc", labels: [:]))
        #expect(!Testcontainers.isRyuk(name: "x", image: "testcontainers/ryuk-like:1", labels: [:]))
    }

    @Test func aMalformedOrLivePIDNeverReadsAsExited() throws {
        #expect(OwnerLabel.processAlive(ProcessInfo.processInfo.processIdentifier))
        #expect(OwnerLabel.processAlive(0))
        #expect(OwnerLabel.processAlive(1))  // launchd: not ours to signal, but alive.
        #expect(!OwnerLabel.processAlive(try exitedPID()))
    }

    @Test func sustainedLoadAlertsOncePerEpisode() {
        var load = SustainedLoad(threshold: 80, duration: 300)
        let start = Date()
        // Seconds from start and CPU percent; returns each sample's result.
        func run(_ samples: [(TimeInterval, Double)]) -> [Bool] {
            samples.map { load.record($0.1, at: start.addingTimeInterval($0.0)) }
        }

        #expect(run([(0, 95), (120, 90), (180, 50), (240, 90), (480, 90)]) == [false, false, false, false, false])
        #expect(run([(540, 90)]) == [true])
        #expect(load.sustained)
        #expect(run([(600, 99)]) == [false], "one alert per episode")
        #expect(run([(660, 10)]) == [false])
        #expect(!load.sustained)
        #expect(run([(720, 90), (2_000, 90)]) == [false, false], "a long gap is not proof of sustained load")
    }
}
