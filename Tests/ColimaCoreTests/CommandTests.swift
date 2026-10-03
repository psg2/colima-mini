import Foundation
import XCTest

@testable import ColimaCore

final class CommandTests: XCTestCase {
    func testLargeOutputDoesNotDeadlock() async throws {
        let result = try await Command.run(
            "/bin/sh", ["-c", "head -c 100000 /dev/zero | tr '\\0' x"], timeout: 5)
        XCTAssertEqual(result.count, 100_000)
    }
    func testStdinIsClosed() async throws {
        let result = try await Command.run(
            "/bin/sh", ["-c", "if read value; then printf open; else printf closed; fi"], timeout: 2)
        XCTAssertEqual(result, "closed")
    }
    func testFailurePreservesUsefulStderr() async {
        do {
            _ = try await Command.run("/bin/sh", ["-c", "printf 'runtime unavailable' >&2; exit 7"])
            XCTFail("Failed command was accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("runtime unavailable")) }
    }
    func testTimeoutKillsUnresponsiveProcess() async throws {
        let start = Date()
        do {
            _ = try await Command.run(
                "/bin/sh", ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.1)
            XCTFail("Unresponsive process completed successfully")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }
    func testChildFindsHomebrewToolsWithLaunchdPath() async throws {
        let path = try await Command.run(
            "/bin/sh", ["-c", "printf %s \"$PATH\""],
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        let directories = path.split(separator: ":")
        XCTAssertTrue(directories.contains("/opt/homebrew/bin"))
        XCTAssertTrue(directories.contains("/usr/local/bin"))
        XCTAssertEqual(directories.first, "/usr/bin")
    }
    func testExplicitExecutableOverrideMustExist() {
        let tools = Toolchain(environment: ["COLIMA_MINI_DOCKER": "/nonexistent/docker"])
        XCTAssertThrowsError(try tools.executable("docker"))
    }
    func testCancellationKillsTermIgnoringChildWithoutWaitingForDeadline() async throws {
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
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: ready.path) && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let pid = try XCTUnwrap(Int32(try String(contentsOf: ready, encoding: .utf8)))
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Canceled command returned success")
        } catch is CancellationError {} catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(kill(pid, 0), -1, "Canceled child remains running")
        XCTAssertEqual(errno, ESRCH)
    }
    func testCombinedOutputPolicyPreservesBothStreamsAndCommandErrors() async throws {
        let output = try await Command.run(
            "/bin/sh", ["-c", "printf first; printf second >&2; printf third"], outputPolicy: .combined)
        XCTAssertEqual(output, "firstsecondthird")
        do {
            _ = try await Command.run(
                "/bin/sh", ["-c", "printf 'combined failure' >&2; exit 7"], outputPolicy: .combined)
            XCTFail("Failed combined-output command was accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("combined failure")) }
    }
}
