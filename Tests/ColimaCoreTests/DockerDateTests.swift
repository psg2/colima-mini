import XCTest

@testable import ColimaCore

final class DockerDateTests: XCTestCase {
    func testDockerTimestampsParseAndTheZeroTimeMeansNever() {
        let expected = Date(timeIntervalSince1970: 1_790_882_960.762)
        XCTAssertEqual(
            DockerDate.parse("2026-10-01T19:29:20.762387404Z")!.timeIntervalSince1970,
            expected.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(
            DockerDate.parse("2026-10-01T16:29:20-03:00")!.timeIntervalSince1970,
            1_790_882_960, accuracy: 0.001)
        XCTAssertEqual(
            DockerDate.parse("2026-10-01T19:29:20.5Z")!.timeIntervalSince1970,
            1_790_882_960.5, accuracy: 0.001)
        XCTAssertNil(DockerDate.parse("0001-01-01T00:00:00Z"))
        XCTAssertNil(DockerDate.parse(""))
        XCTAssertNil(DockerDate.parse("yesterday"))
    }
}
