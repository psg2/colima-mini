import Foundation
import Testing

@testable import ColimaCore

struct UnusedContainersTests {
    // Fake docker and lsof executables serve a fixed set of containers. Any
    // docker command other than a read is recorded in `changes` and fails.
    // FAKE_DOCKER_REMOVED names a container removed while the scan runs.
    private let docker = #"""
        #!/bin/sh
        dir="$FAKE_DOCKER_DIR"
        [ "$1 $2" = "--context colima" ] || exit 90
        shift 2
        if [ "${FAKE_DOCKER_FAIL:-}" = "$1" ]; then echo "synthetic Docker failure" >&2; exit 1; fi
        case "$1" in
          ps) cat "$dir/ids" ;;
          inspect)
            cat "$dir/inspect.json"
            if [ -n "${FAKE_DOCKER_REMOVED:-}" ]; then echo "error: no such object: gone00000001" >&2; exit 1; fi ;;
          stats)
            calls=$(($(cat "$dir/stats-calls" 2>/dev/null || echo 0) + 1))
            echo "$calls" >"$dir/stats-calls"
            cat "$dir/stats$calls" ;;
          logs)
            eval "id=\${$#}"
            if [ "$id" = "${FAKE_DOCKER_REMOVED:-}" ]; then
              echo "Error response from daemon: No such container: $id" >&2; exit 1
            fi
            # Like Postgres, write the log line to stderr.
            if [ -f "$dir/logs/$id" ]; then cat "$dir/logs/$id" >&2; fi ;;
          *) echo "$*" >>"$dir/changes"; exit 1 ;;
        esac
        """#
    // A node process connected to host port 55001, plus Docker's side of a
    // forwarded connection, which is not a client.
    private let lsof = #"""
        #!/bin/sh
        case "${FAKE_LSOF_MODE:-}" in
          fail) echo "synthetic lsof failure" >&2; exit 1 ;;
          empty) exit 1 ;;
        esac
        cat <<'OUT'
        COMMAND     PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node      31993 demo   21u  IPv4 0x1111      0t0  TCP 127.0.0.1:61234->127.0.0.1:55001 (ESTABLISHED)
        com.docke   900 demo   80u  IPv4 0x2222      0t0  TCP 127.0.0.1:55002->127.0.0.1:61235 (ESTABLISHED)
        OUT
        """#

    private static func ago(_ seconds: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date().addingTimeInterval(-seconds)).replacingOccurrences(
            of: "Z", with: ".123456789Z")
    }
    private static func container(
        _ id: String, _ name: String, project: String? = nil, folder: String? = nil, port: String? = nil,
        image: String = "postgres:18", labels: [String: String] = [:], started: TimeInterval,
        finished: TimeInterval? = nil
    ) -> [String: Any] {
        let compose =
            project.map {
                ["com.docker.compose.project": $0, "com.docker.compose.project.working_dir": folder ?? ""]
            } ?? [:]
        return [
            "Id": id, "Name": "/" + name, "Created": ago(started),
            "State": [
                "Running": finished == nil, "StartedAt": ago(started),
                "FinishedAt": finished.map(ago) ?? "0001-01-01T00:00:00Z",
            ],
            "Config": ["Image": image, "Labels": compose.merging(labels) { $1 }],
            "NetworkSettings": [
                "Ports": port.map { ["5432/tcp": [["HostIp": "127.0.0.1", "HostPort": $0]]] } ?? [:]
            ],
        ]
    }

    // `extra` adds containers to the fixed set; `extraRunning` lists which of
    // them are running, so `docker stats` reports them.
    private func scan(
        _ environment: [String: String] = [:], extra: (_ live: String) -> [[String: Any]] = { _ in [] },
        extraRunning: [String] = []
    ) async throws -> (groups: [SweepGroup], changes: String?) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-unused-" + UUID().uuidString)
        let live = directory.appendingPathComponent("live-project")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("logs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let day: TimeInterval = 86_400
        func container(
            _ id: String, _ name: String, project: String? = nil, folder: String? = nil, port: String? = nil,
            started: TimeInterval, finished: TimeInterval? = nil
        ) -> [String: Any] {
            Self.container(id, name, project: project, folder: folder, port: port, started: started, finished: finished)
        }
        let containers =
            [
                container("orphan000001", "gone-db-1", project: "gone", folder: "/nonexistent/worktree", started: 3 * day),
                container("orphan000002", "gone-web-1", project: "gone", folder: "/nonexistent/worktree", started: 3 * day),
                container("busy00000001", "busy-pg", port: "55001", started: 5 * day),
                container("chatty000001", "chatty", started: 5 * day),
                container("idle00000001", "old-db-1", project: "old", folder: live.path, started: 5 * day),
                container("fresh0000001", "fresh-pg", port: "55003", started: 5 * day),
                container(
                    "stale0000001", "stale-db-1", project: "stale", folder: live.path, started: 9 * day, finished: 8 * day),
                container("paused000001", "paused-pg", started: 2 * day, finished: 1_800),
            ] + extra(live.path)
        try JSONSerialization.data(withJSONObject: containers).write(
            to: directory.appendingPathComponent("inspect.json"))
        try Data(containers.map { $0["Id"] as! String }.joined(separator: "\n").utf8).write(
            to: directory.appendingPathComponent("ids"))
        let running = ["busy00000001", "chatty000001", "idle00000001", "fresh0000001", "orphan000001"] + extraRunning
        let stats = running.map { "\($0)\t1kB / 1kB" }.joined(separator: "\n")
        try Data(stats.utf8).write(to: directory.appendingPathComponent("stats1"))
        try Data(stats.replacingOccurrences(of: "chatty000001\t1kB", with: "chatty000001\t9kB").utf8).write(
            to: directory.appendingPathComponent("stats2"))
        for (id, line) in [
            "busy00000001": Self.ago(4 * day) + " LOG: checkpoint complete",
            "idle00000001": Self.ago(3 * day) + " LOG: checkpoint complete",
            "fresh0000001": Self.ago(600) + " LOG: checkpoint complete",
        ] {
            try Data((line + "\n").utf8).write(to: directory.appendingPathComponent("logs/" + id))
        }
        for (name, program) in [("docker", docker), ("lsof", lsof)] {
            let url = directory.appendingPathComponent(name)
            try Data((program + "\n").utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        var env = ProcessInfo.processInfo.environment
        env["COLIMA_MINI_DOCKER"] = directory.appendingPathComponent("docker").path
        env["COLIMA_MINI_LSOF"] = directory.appendingPathComponent("lsof").path
        env["FAKE_DOCKER_DIR"] = directory.path
        env.merge(environment) { $1 }
        let groups = try await Backend(toolchain: Toolchain(environment: env)).unusedContainers(sample: 0)
        let changes = try? String(contentsOf: directory.appendingPathComponent("changes"), encoding: .utf8)
        return (groups, changes)
    }

    @Test func scanGivesEachGroupAVerdictWithoutChangingContainers() async throws {
        let (groups, changes) = try await scan()

        #expect(
            groups.map { "\($0.verdict.rawValue) \($0.name)" } == [
                "orphan gone", "stale stale", "idle old", "recent fresh-pg", "active busy-pg", "active chatty",
                "stopped paused-pg",
            ])
        let byName = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0) })
        #expect(byName["gone"]?.containerIDs == ["orphan000001", "orphan000002"])
        #expect(byName["gone"]?.project == "gone")
        #expect(byName["gone"]?.reason == "folder gone: /nonexistent/worktree")
        #expect(byName["busy-pg"]?.reason == "clients: node(31993)")
        #expect(byName["chatty"]?.reason == "network traffic during sample")
        #expect(byName["old"]?.reason == "no clients, no traffic, quiet for 3d")
        #expect(byName["fresh-pg"]?.reason == "no clients, no traffic, last log 10m ago")
        #expect(byName["stale"]?.reason == "not running for 8d")
        #expect(byName["paused-pg"]?.reason == "stopped 30m ago")
        #expect(byName["paused-pg"]?.project == nil)
        #expect(changes == nil, "the scan changed containers")
    }

    // Leaked test containers: a session whose Ryuk is gone, a live session
    // where one creator exited, and a container whose owner folder is gone.
    @Test func scanGroupsTestcontainersBySessionAndFlagsOwnersThatAreGone() async throws {
        let deadPID = String(try exitedPID())
        let alivePID = String(ProcessInfo.processInfo.processIdentifier)
        let day: TimeInterval = 86_400
        func tc(_ session: String, _ extra: [String: String] = [:]) -> [String: String] {
            ["org.testcontainers": "true", "org.testcontainers.session-id": session].merging(extra) { $1 }
        }
        let (groups, changes) = try await scan(
            extra: { live in
                [
                    Self.container("tcdead000001", "brave_pg", labels: tc("deadsession01"), started: 6 * day),
                    Self.container(
                        "tcdead000002", "calm_redis", labels: tc("deadsession01"), started: 6 * day,
                        finished: 5 * day),
                    Self.container(
                        "ryuklive0001", "testcontainers-ryuk-livesession01", image: "testcontainers/ryuk:0.11.0",
                        started: 2 * day),
                    Self.container(
                        "tclive000001", "eager_pg", labels: tc("livesession01", ["dev.owner.pid": alivePID]),
                        started: 2 * day),
                    Self.container(
                        "tclive000002", "lost_pg",
                        labels: tc("livesession01", ["dev.owner.pid": deadPID, "dev.owner.working_dir": live]),
                        started: 2 * day),
                    Self.container(
                        "owned0000001", "stray-api", labels: ["dev.owner.working_dir": "/nonexistent/wt"],
                        started: day),
                ]
            }, extraRunning: ["tcdead000001", "ryuklive0001", "tclive000001", "tclive000002", "owned0000001"])

        let byName = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0) })
        let dead = try #require(byName["testcontainers deadsession01"])
        #expect(dead.verdict == .orphan)
        #expect(dead.containerIDs == ["tcdead000001", "tcdead000002"])
        #expect(dead.reason.contains("Ryuk gone"))
        #expect(dead.project == "testcontainers deadsession01")

        let lost = try #require(byName["testcontainers livesession01 · owner gone"])
        #expect(lost.verdict == .orphan)
        #expect(lost.containerIDs == ["tclive000002"])
        #expect(lost.reason == "owner process \(deadPID) exited")

        let live = try #require(byName["testcontainers livesession01"])
        #expect(live.verdict != .orphan)
        #expect(Set(live.containerIDs) == ["ryuklive0001", "tclive000001"])
        #expect(live.reason.hasPrefix("Ryuk alive"))

        #expect(byName["stray-api"]?.verdict == .orphan)
        #expect(byName["stray-api"]?.reason == "owner folder gone: /nonexistent/wt")
        #expect(!groups.contains { $0.name == "Standalone" })
        #expect(changes == nil, "the scan changed containers")
    }

    @Test func scanAcceptsLsofFindingNoConnections() async throws {
        let (groups, _) = try await scan(["FAKE_LSOF_MODE": "empty"])

        #expect(groups.first { $0.name == "busy-pg" }?.verdict == .idle)
    }

    // Test suites create and remove containers constantly, so some vanish
    // between listing and inspecting or reading their logs.
    @Test func scanSkipsContainersRemovedDuringTheScan() async throws {
        let (groups, _) = try await scan(["FAKE_DOCKER_REMOVED": "idle00000001"])

        #expect(groups.count == 7)
        #expect(groups.first { $0.name == "fresh-pg" }?.verdict == .recent)
    }

    // A failed probe must not look like an empty or idle result.
    @Test func scanFailsWhenAProbeFails() async throws {
        let failures: [[String: String]] =
            ["ps", "inspect", "stats", "logs"].map { ["FAKE_DOCKER_FAIL": $0] } + [
                ["FAKE_LSOF_MODE": "fail"]
            ]
        for failure in failures {
            do {
                _ = try await scan(failure)
                Issue.record("\(failure) was accepted")
            } catch {
                #expect(error.localizedDescription.contains("synthetic"), "\(failure): \(error)")
            }
        }
    }

    @Test func reportListsVerdictsAndWhatCanBeCleanedUp() {
        let report = UnusedContainerScan.report([
            SweepGroup(verdict: .stale, name: "worker", project: nil, reason: "not running for 2d", containerIDs: ["c"]),
            SweepGroup(
                verdict: .recent, name: "demo", project: "demo", reason: "last log 5m ago", containerIDs: ["a", "b"]),
        ])

        #expect(report.contains("stale    worker "))
        #expect(report.contains("recent   demo (2) "))
        #expect(report.hasSuffix("1 orphan or stale group(s) can be removed and 0 idle group(s) stopped."))
        #expect(UnusedContainerScan.report([]) == "No containers.")
    }
}
