import Foundation
import XCTest

@testable import ColimaCore

final class BackendTests: XCTestCase {
    // Real subprocesses provide a small local runtime. Assertions inspect the
    // resulting VM/container state rather than the order of implementation calls.
    // The fake runtime keeps its state as files in `state/`: `vm`, one `docker ps`
    // line per container in `containers`, `stats`, and the optional failure
    // switches `fail_stats`, `remove_on_start` and `fail_restore`.
    func runtime(_ body: (Backend, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-backend-" + UUID().uuidString)
        let state = directory.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("colima.yaml")
        try Data("cpu: 2\nmemory: 2\ndisk: 100\nautoActivate: true\n".utf8).write(to: config)
        let fixture = try SnapshotTests().fixture()
        for (name, value) in ["vm": fixture.vm, "containers": fixture.containers, "stats": fixture.stats] {
            try Data((value + "\n").utf8).write(to: state.appendingPathComponent(name))
        }
        let program = #"""
            #!/bin/sh
            s="$COLIMA_TEST_STATE"
            fail() { echo "$1" >&2; exit 1; }
            [ -z "${DOCKER_HOST+set}" ] || fail 'foreign Docker host leaked into runtime'
            # Rewrites State and Status on the container lines whose ID is in $1.
            set_state() {
              awk -v ids=" $1 " -v state="$2" -v status="$3" '{
                match($0, /"ID": *"[^"]*"/); id = substr($0, RSTART, RLENGTH - 1); sub(/.*"/, "", id)
                if (ids == " * " || index(ids, " " id " ")) {
                  sub(/"State": *"[^"]*"/, "\"State\": \"" state "\""); sub(/"Status": *"[^"]*"/, "\"Status\": \"" status "\"")
                }
                print }' "$s/containers" >"$s/containers.new" && mv "$s/containers.new" "$s/containers"
            }
            setting() { sed -n "s/^$1: *//p" "$COLIMA_TEST_CONFIG"; }
            if [ "$(basename "$0")" = colima ]; then
              case "$1" in
                list) cat "$s/vm" ;;
                stop)
                  sed -E 's/"status": *"[^"]*"/"status": "Stopped"/' "$s/vm" >"$s/vm.new" && mv "$s/vm.new" "$s/vm"
                  set_state '*' exited 'Exited (0) just now' ;;
                start)
                  memory=$(awk -v gib="$(setting memory)" 'BEGIN { printf "%d", gib * 1073741824 }')
                  disk=$(awk -v gib="$(setting disk)" 'BEGIN { printf "%d", gib * 1073741824 }')
                  sed -E -e 's/"status": *"[^"]*"/"status": "Running"/' -e "s/\"cpus\": *[0-9]+/\"cpus\": $(setting cpu)/" \
                    -e "s/\"memory\": *[0-9]+/\"memory\": $memory/" -e "s/\"disk\": *[0-9]+/\"disk\": $disk/" \
                    "$s/vm" >"$s/vm.new" && mv "$s/vm.new" "$s/vm"
                  if [ -f "$s/remove_on_start" ]; then
                    grep -v "\"ID\": *\"$(cat "$s/remove_on_start")\"" "$s/containers" >"$s/containers.new"
                    mv "$s/containers.new" "$s/containers"
                  fi ;;
                *) fail 'unsupported VM operation' ;;
              esac
              exit 0
            fi
            [ "$1 $2" = "--context colima" ] || fail 'wrong Docker context'
            shift 2
            case "$1" in
              ps) cat "$s/containers" ;;
              stats)
                [ ! -f "$s/fail_stats" ] || fail 'synthetic metrics failure'
                cat "$s/stats" ;;
              start)
                shift
                ids=""
                for id in "$@"; do
                  [ "$id" = "$(cat "$s/fail_restore" 2>/dev/null)" ] || ids="$ids $id"
                done
                set_state "$ids" running 'Up just now' ;;
              logs)
                eval "id=\${$#}"
                case "$id" in
                  split)
                    printf '2026-10-02T12:00:02Z hel'
                    sleep 0.2
                    echo 'lo from split' ;;
                  endless)
                    printf '%s' $$ >"$s/../follower.pid"
                    echo '2026-10-02T12:00:00Z first line'
                    exec sleep 60 ;;
                  *)
                    echo '2026-10-02T12:00:00Z stdout log'
                    echo '2026-10-02T12:00:01Z stderr log' >&2
                    printf '2026-10-02T12:00:01Z equal timestamp\nmultiline body\n' ;;
                esac ;;
              *) fail 'unsupported container operation' ;;
            esac
            """#
        for name in ["docker", "colima"] {
            let url = directory.appendingPathComponent(name)
            try Data((program + "\n").utf8).write(to: url)
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
    private func state(_ config: URL, _ name: String) -> URL {
        config.deletingLastPathComponent().appendingPathComponent("state").appendingPathComponent(name)
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
            let containers = state(config, "containers")
            let text = try String(contentsOf: containers, encoding: .utf8)
            let rows = try Snapshot.lines(text, as: Container.self)
            let previouslyStopped = try XCTUnwrap(rows.first { !$0.running })
            let encoded = try text.split(separator: "\n").map { original -> String in
                var value = try JSONSerialization.jsonObject(with: Data(original.utf8)) as! [String: Any]
                value["State"] = value["ID"] as? String == previouslyStopped.id ? "running" : "exited"
                value["Status"] =
                    value["ID"] as? String == previouslyStopped.id ? "Up just now" : "Exited (0) just now"
                return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
            }
            try Data((encoded.joined(separator: "\n") + "\n").utf8).write(to: containers)
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
                try Data(running.id.utf8).write(to: state(config, failure))
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
            try Data().write(to: state(config, "fail_stats"))
            try await backend.apply(
                ResourceSettings(cpus: 1, memoryGiB: 2), restart: true)
            let after = try Snapshot.decode(
                vm: String(contentsOf: state(config, "vm"), encoding: .utf8),
                containers: String(contentsOf: state(config, "containers"), encoding: .utf8), stats: "")
            XCTAssertEqual(after.vm.cpus, 1)
            XCTAssertEqual(
                Set(after.containers.filter(\.running).map(\.id)),
                Set(before.containers.filter(\.running).map(\.id)))
        }
    }
}
