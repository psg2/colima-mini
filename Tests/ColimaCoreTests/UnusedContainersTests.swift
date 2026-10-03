import Foundation
import XCTest

@testable import ColimaCore

final class UnusedContainersTests: XCTestCase {
    // Runs the bundled scanner against the fake Docker CLI, so the app decodes
    // what the script really prints.
    func testScanReturnsGroupsWithVerdictsAndContainerIDsWithoutChangingAnything() async throws {
        let helpers = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("SweepHelpers")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-unused-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3 * 86_400))
        func container(_ id: String, _ name: String, project: String?, running: Bool) -> [String: Any] {
            [
                "Id": id, "Name": "/" + name, "Created": stamp,
                "State": [
                    "Running": running, "StartedAt": stamp,
                    "FinishedAt": running ? "0001-01-01T00:00:00Z" : stamp,
                ],
                "Config": [
                    "Labels": project.map {
                        [
                            "com.docker.compose.project": $0,
                            "com.docker.compose.project.working_dir": "/nonexistent/" + $0,
                        ]
                    } ?? [:]
                ],
                "NetworkSettings": ["Ports": [:]],
            ]
        }
        let state: [String: Any] = [
            "containers": [
                container("gone1", "gone-db-1", project: "gone", running: true),
                container("gone2", "gone-web-1", project: "gone", running: true),
                container("old1", "old-worker", project: nil, running: false),
            ],
            "logs": [:], "networks": [:],
        ]
        let stateURL = directory.appendingPathComponent("state.json")
        try JSONSerialization.data(withJSONObject: state).write(to: stateURL)
        let log = directory.appendingPathComponent("docker.log")
        var env = ProcessInfo.processInfo.environment
        env["COLIMA_MINI_DOCKER"] = helpers.appendingPathComponent("fake-docker").path
        env["DOCKER_SWEEP_LSOF"] = helpers.appendingPathComponent("fake-lsof").path
        env["FAKE_DOCKER_STATE"] = stateURL.path
        env["FAKE_DOCKER_LOG"] = log.path
        env["FAKE_LSOF_MODE"] = "empty"

        let groups = try await Backend(toolchain: Toolchain(environment: env)).unusedContainers()

        XCTAssertEqual(
            groups,
            [
                SweepGroup(
                    verdict: .orphan, name: "gone", project: "gone",
                    reason: "folder gone: /nonexistent/gone", containerIDs: ["gone1", "gone2"]),
                SweepGroup(
                    verdict: .stale, name: "old-worker", project: nil, reason: "not running for 3d",
                    containerIDs: ["old1"]),
            ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path), "the scan changed containers")
    }
}
