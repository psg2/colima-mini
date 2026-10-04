import Foundation
import Testing

@testable import ColimaCore

struct VolumeRemovalTests {
    @Test func removalNeverForcesAndRejectsOptionLikeNames() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-volumes-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = directory.appendingPathComponent("commands")
        let program = #"""
            #!/bin/sh
            [ "$1 $2" = "--context colima" ] || exit 3
            shift 2
            echo "$*" >> "$VOLUME_RECORD"
            """#
        let docker = directory.appendingPathComponent("docker")
        try Data(program.utf8).write(to: docker)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: docker.path)
        var env = ProcessInfo.processInfo.environment
        env["COLIMA_MINI_DOCKER"] = docker.path
        env["VOLUME_RECORD"] = record.path
        let backend = Backend(toolchain: Toolchain(environment: env))

        try await backend.removeVolume("old_db")
        for invalid in ["", "--force"] {
            do {
                try await backend.removeVolume(invalid)
                Issue.record("Accepted \(invalid)")
            } catch {}
        }
        #expect(try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init) == ["volume rm old_db"])
        do {
            try await Backend(fixture: try SnapshotTests().fixture()).removeVolume("old_db")
            Issue.record("Sample mode removed a volume")
        } catch {}
    }
}
