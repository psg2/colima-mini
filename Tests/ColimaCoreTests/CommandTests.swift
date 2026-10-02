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
  func testExplicitExecutableOverrideMustExist() {
    let tools = Toolchain(environment: ["COLIMA_MINI_DOCKER": "/nonexistent/docker"])
    XCTAssertThrowsError(try tools.executable("docker"))
  }
}
