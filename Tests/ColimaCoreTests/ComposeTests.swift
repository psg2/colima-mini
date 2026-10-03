import Foundation
import XCTest

@testable import ColimaCore

final class ComposeTests: XCTestCase {
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
        let program = #"""
            #!/usr/bin/env python3
            import json, os, sys
            a = sys.argv[1:]
            if a[:2] != ['--context', 'colima']: sys.exit('foreign Docker runtime')
            a = a[2:]
            if a[0] == 'inspect':
                print(open(os.environ['COMPOSE_LABELS']).read())
            else:
                with open(os.environ['COMPOSE_RECORD'], 'a') as f: f.write(json.dumps(a) + '\n')
            """#
        let docker = directory.appendingPathComponent("docker")
        try Data(program.utf8).write(to: docker)
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

    func testUpRunsInTheProjectFolderWithEveryComposeFile() async throws {
        try await run(folder: true) { backend, folder, commands in
            let project = try await backend.composeProject("demo", containerID: "abc123")
            try await backend.compose(.up, project: project)
            let arguments = try JSONDecoder().decode(
                [String].self, from: Data(try XCTUnwrap(commands().first).utf8))
            XCTAssertEqual(
                arguments,
                [
                    "compose", "--project-name", "demo", "--project-directory", folder.path,
                    "--file", folder.appendingPathComponent("compose.yaml").path,
                    "--file", folder.appendingPathComponent("compose.override.yaml").path,
                    "up", "--detach",
                ])
        }
    }

    func testDownWithVolumesWorksAfterTheFolderIsDeletedButUpDoesNot() async throws {
        try await run(folder: false) { backend, _, commands in
            let project = try await backend.composeProject("demo", containerID: "abc123")
            do {
                try await backend.compose(.up, project: project)
                XCTFail("Up ran without compose files")
            } catch {}
            XCTAssertEqual(try commands(), [])
            try await backend.compose(.downVolumes, project: project)
            XCTAssertEqual(
                try commands(), [#"["compose", "--project-name", "demo", "down", "--volumes"]"#])
        }
    }

    func testAContainerFromAnotherProjectIsRejected() async throws {
        try await run(folder: true) { backend, _, commands in
            do {
                _ = try await backend.composeProject("other", containerID: "abc123")
                XCTFail("Accepted a container from another project")
            } catch {}
            XCTAssertEqual(try commands(), [])
        }
    }
}
