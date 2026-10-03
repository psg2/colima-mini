import Foundation
import XCTest

@testable import ColimaCore

final class ImageActionTests: XCTestCase {
    private func image(_ repository: String, _ tag: String, users: [String] = []) -> DockerImage {
        DockerImage(
            imageID: "sha256:" + String(repeating: "a", count: 64), repository: repository, tag: tag,
            sizeBytes: 1, sharedBytes: 0, uniqueBytes: 1, containerIDs: users, referencesAvailable: true)
    }

    func testRemovalTargetsTheTagOrTheIDWithoutForceAndPullNeedsATag() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-images-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = directory.appendingPathComponent("commands")
        let program = #"""
            #!/bin/sh
            [ "$1 $2" = "--context colima" ] || exit 3
            shift 2
            echo "$*" >> "$IMAGE_RECORD"
            """#
        let docker = directory.appendingPathComponent("docker")
        try Data(program.utf8).write(to: docker)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: docker.path)
        var env = ProcessInfo.processInfo.environment
        env["COLIMA_MINI_DOCKER"] = docker.path
        env["IMAGE_RECORD"] = record.path
        let backend = Backend(toolchain: Toolchain(environment: env))

        try await backend.removeImage(image("postgres", "17"))
        try await backend.removeImage(image("<none>", "<none>"))
        try await backend.pullImage(image("postgres", "18"))
        do {
            try await backend.pullImage(image("<none>", "<none>"))
            XCTFail("Pulled an untagged image")
        } catch {}

        XCTAssertEqual(
            try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init),
            [
                "image rm postgres:17", "image rm sha256:" + String(repeating: "a", count: 64),
                "pull --quiet postgres:18",
            ])
        XCTAssertTrue(image("redis", "7").unused)
        XCTAssertFalse(image("redis", "7", users: ["c1"]).unused)
    }
}
