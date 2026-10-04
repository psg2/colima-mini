import Foundation
import Testing

@testable import ColimaCore

struct CommandTests {
    @Test func largeOutputDoesNotDeadlock() async throws {
        let result = try await Command.run(
            "/bin/sh", ["-c", "head -c 100000 /dev/zero | tr '\\0' x"], timeout: 5)
        #expect(result.count == 100_000)
    }
    @Test func stdinIsClosed() async throws {
        let result = try await Command.run(
            "/bin/sh", ["-c", "if read value; then printf open; else printf closed; fi"], timeout: 2)
        #expect(result == "closed")
    }
    @Test func failurePreservesUsefulStderr() async {
        do {
            _ = try await Command.run("/bin/sh", ["-c", "printf 'runtime unavailable' >&2; exit 7"])
            Issue.record("Failed command was accepted")
        } catch { #expect(error.localizedDescription.contains("runtime unavailable")) }
    }
    @Test func timeoutKillsUnresponsiveProcess() async throws {
        let start = Date()
        do {
            _ = try await Command.run(
                "/bin/sh", ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.1)
            Issue.record("Unresponsive process completed successfully")
        } catch { #expect(error.localizedDescription.contains("timed out")) }
        #expect(Date().timeIntervalSince(start) < 4)
    }
    @Test func childFindsHomebrewToolsWithLaunchdPath() async throws {
        let path = try await Command.run(
            "/bin/sh", ["-c", "printf %s \"$PATH\""],
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        let directories = path.split(separator: ":")
        #expect(directories.contains("/opt/homebrew/bin"))
        #expect(directories.contains("/usr/local/bin"))
        #expect(directories.first == "/usr/bin")
    }
    @Test func explicitExecutableOverrideMustExist() {
        let tools = Toolchain(environment: ["COLIMA_MINI_DOCKER": "/nonexistent/docker"])
        #expect(throws: (any Error).self) { try tools.executable("docker") }
    }
    @Test func cancellationKillsTermIgnoringChildWithoutWaitingForDeadline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ready = directory.appendingPathComponent("ready")
        let task = Task {
            try await Command.run(
                "/bin/sh",
                ["-c", "trap '' TERM; printf '%s' \"$$\" > \"$COLIMA_TEST_READY\"; while :; do :; done"],
                timeout: 30, environment: ["COLIMA_TEST_READY": ready.path])
        }
        defer { task.cancel() }
        // The shell creates the file before it writes its PID, so wait for the PID.
        func readPID() -> Int32? { (try? String(contentsOf: ready, encoding: .utf8)).flatMap { Int32($0) } }
        let deadline = Date().addingTimeInterval(5)
        while readPID() == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let pid = try #require(readPID())
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Canceled command returned success")
        } catch is CancellationError {} catch {
            Issue.record("Expected CancellationError, received \(error)")
        }
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(kill(pid, 0) == -1, "Canceled child remains running")
        #expect(errno == ESRCH)
    }
    @Test func combinedOutputPolicyPreservesBothStreamsAndCommandErrors() async throws {
        let output = try await Command.run(
            "/bin/sh", ["-c", "printf first; printf second >&2; printf third"], outputPolicy: .combined)
        #expect(output == "firstsecondthird")
        do {
            _ = try await Command.run(
                "/bin/sh", ["-c", "printf 'combined failure' >&2; exit 7"], outputPolicy: .combined)
            Issue.record("Failed combined-output command was accepted")
        } catch { #expect(error.localizedDescription.contains("combined failure")) }
    }
}
