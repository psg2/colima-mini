import Foundation
import Testing

@testable import ColimaCore

struct ComposeTests {
    private func run(
        folder exists: Bool, body: (Backend, URL, () throws -> [String]) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-compose-" + UUID().uuidString)
        let project = directory.appendingPathComponent("my project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = ["compose.yaml", "compose.override.yaml"].map {
            project.appendingPathComponent($0).path
        }
        for file in files { FileManager.default.createFile(atPath: file, contents: Data()) }
        if !exists { try FileManager.default.removeItem(at: project) }
        let labels: [String: String] = [
            "com.docker.compose.project": "demo",
            "com.docker.compose.project.working_dir": project.path,
            "com.docker.compose.project.config_files": files.joined(separator: ","),
        ]
        let labelsURL = directory.appendingPathComponent("labels.json")
        try JSONSerialization.data(withJSONObject: labels).write(to: labelsURL)
        let record = directory.appendingPathComponent("commands")
        // Records each command as a JSON array of its arguments.
        let program = #"""
            #!/bin/sh
            [ "$1 $2" = "--context colima" ] || { echo 'foreign Docker runtime' >&2; exit 1; }
            shift 2
            if [ "$1" = inspect ]; then cat "$COMPOSE_LABELS"; echo; exit 0; fi
            arguments=''
            for argument in "$@"; do arguments="$arguments${arguments:+, }\"$argument\""; done
            echo "[$arguments]" >>"$COMPOSE_RECORD"
            """#
        let docker = directory.appendingPathComponent("docker")
        try Data((program + "\n").utf8).write(to: docker)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: docker.path)
        var env = ProcessInfo.processInfo.environment
        env["COLIMA_MINI_DOCKER"] = docker.path
        env["COMPOSE_LABELS"] = labelsURL.path
        env["COMPOSE_RECORD"] = record.path
        let commands = {
            guard FileManager.default.fileExists(atPath: record.path) else { return [String]() }
            return try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init)
        }
        try await body(Backend(toolchain: Toolchain(environment: env)), project, commands)
    }

    @Test func upRunsInTheProjectFolderWithEveryComposeFile() async throws {
        try await run(folder: true) { backend, folder, commands in
            let project = try await backend.composeProject("demo", containerID: "abc123")
            try await backend.compose(.up, project: project)
            let arguments = try JSONDecoder().decode(
                [String].self, from: Data(try #require(commands().first).utf8))
            #expect(
                arguments == [
                    "compose", "--project-name", "demo", "--project-directory", folder.path,
                    "--file", folder.appendingPathComponent("compose.yaml").path,
                    "--file", folder.appendingPathComponent("compose.override.yaml").path,
                    "up", "--detach",
                ])
        }
    }

    @Test func downWithVolumesWorksAfterTheFolderIsDeletedButUpDoesNot() async throws {
        try await run(folder: false) { backend, _, commands in
            let project = try await backend.composeProject("demo", containerID: "abc123")
            do {
                try await backend.compose(.up, project: project)
                Issue.record("Up ran without compose files")
            } catch {}
            let recorded = try commands()
            #expect(recorded.isEmpty)
            try await backend.compose(.downVolumes, project: project)
            #expect(try commands() == [#"["compose", "--project-name", "demo", "down", "--volumes"]"#])
        }
    }

    @Test func aContainerFromAnotherProjectIsRejected() async throws {
        try await run(folder: true) { backend, _, commands in
            do {
                _ = try await backend.composeProject("other", containerID: "abc123")
                Issue.record("Accepted a container from another project")
            } catch {}
            let recorded = try commands()
            #expect(recorded.isEmpty)
        }
    }
}
