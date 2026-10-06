import Foundation
import Testing

@testable import ColimaCore

struct ContainerStateTests {
    private func container(
        _ id: String = "abc123", state: String, status: String, ports: String = "",
        labels: String = "com.docker.compose.project=demo"
    ) throws -> Container {
        let row: [String: String] = [
            "ID": id, "Names": "demo-\(id)-1", "Image": "postgres:18", "State": state,
            "Status": status, "Ports": ports, "Labels": labels,
        ]
        return try JSONDecoder().decode(Container.self, from: JSONEncoder().encode(row))
    }

    @Test func agentWorktreesExplainGeneratedProjectNames() {
        let home = "/Users/dev"
        let claude = ProjectOrigin(
            path: "/Users/dev/.claude-worktrees/eventos/interesting-morse-28202f", home: home)
        #expect(claude.kind == .claude)
        #expect(claude.repository == "eventos")
        #expect(claude.worktree == "interesting-morse-28202f")
        #expect(claude.displayPath == "~/.claude-worktrees/eventos/interesting-morse-28202f")

        let inRepository = ProjectOrigin(
            path: "/Users/dev/code/shop/.claude/worktrees/quiet-fox", home: home)
        #expect(inRepository.kind == .claude)
        #expect(inRepository.repository == "shop")

        let codex = ProjectOrigin(path: "/Users/dev/.codex/worktrees/be28/backstage", home: home)
        #expect(codex.kind == .codex)
        #expect(codex.repository == "backstage")
        #expect(codex.summary == "Codex worktree · backstage")

        let orca = ProjectOrigin(
            path: "/Users/dev/orca/workspaces/backstage/ope-1889-stack/w606", home: home)
        #expect(orca.kind == .orca)
        #expect(orca.repository == "backstage")
        #expect(orca.worktree == "ope-1889-stack/w606")

        let plain = ProjectOrigin(path: "/Users/dev/workspace/eventos/", home: home)
        #expect(plain.kind == .folder)
        #expect(plain.summary == "eventos")
        // A sibling directory that merely shares the home prefix isn't abbreviated.
        #expect(ProjectOrigin(path: "/Users/developer/app", home: home).displayPath == "/Users/developer/app")
    }

    @Test func originReportsAFolderRemovedAfterComposeStarted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-origin-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let row = try container(
            state: "running", status: "Up 1 hour",
            labels:
                "com.docker.compose.project=demo,com.docker.compose.project.working_dir=\(folder.path)"
        )
        #expect(row.origin?.exists() == true)
        try FileManager.default.removeItem(at: folder)
        #expect(row.origin?.exists() == false)
        #expect(try container(state: "running", status: "Up 1 hour").origin == nil)
    }

    @Test func publishedPortsMergeAddressFamiliesAndSkipUnpublishedPorts() throws {
        let postgres = try container(
            state: "running", status: "Up 2 hours",
            ports: "0.0.0.0:32934->5432/tcp, [::]:32934->5432/tcp")
        #expect(postgres.publishedPorts.map(\.label) == ["32934→5432"])
        #expect(postgres.publishedPorts.first?.address == "localhost:32934")

        let localstack = try container(
            state: "running", status: "Up 2 hours",
            ports: "4510-4559/tcp, 5678/tcp, 127.0.0.1:32772->4566/tcp, 192.168.5.2:9000->9000/tcp")
        #expect(localstack.publishedPorts.map(\.hostPort) == [32772])

        let dns = try container(
            state: "running", status: "Up 1 minute", ports: "0.0.0.0:5353->53/udp")
        #expect(dns.publishedPorts.first?.url(scheme: "http") == nil)
    }
    @Test func endpointsUseHTTPSForContainerPort443AndSkipUDP() throws {
        let proxy = try container(
            state: "running", status: "Up 2 hours",
            ports: "0.0.0.0:8443->443/tcp, [::]:8443->443/tcp, 0.0.0.0:8080->80/tcp, 0.0.0.0:5353->53/udp")
        #expect(
            proxy.endpoints.map(\.absoluteString) == ["https://localhost:8443", "http://localhost:8080"])
    }

    @Test func conditionSeparatesHealthFromExitCodes() throws {
        let cases: [(String, String, ContainerCondition, Bool)] = [
            ("running", "Up 2 hours (healthy)", .healthy, false),
            ("running", "Up 3 minutes (unhealthy)", .unhealthy, true),
            ("running", "Up 5 seconds (health: starting)", .starting, false),
            ("running", "Up 20 hours", .running, false),
            ("exited", "Exited (0) 3 hours ago", .exited(0), false),
            ("exited", "Exited (137) 1 minute ago", .exited(137), true),
            ("restarting", "Restarting (1) 4 seconds ago", .restarting, true),
        ]
        for (state, status, condition, failed) in cases {
            let row = try container(state: state, status: status)
            #expect(row.condition == condition, "\(status)")
            #expect(row.needsAttention == failed, "\(status)")
        }
        #expect(try container(state: "running", status: "Up 2 hours (healthy)").uptime == "Up 2 hours")
    }

    @Test func alertsReportOnlyNewFailures() throws {
        let before = [
            try container("a", state: "running", status: "Up 1 hour"),
            try container("b", state: "running", status: "Up 1 hour (healthy)"),
            try container("c", state: "exited", status: "Exited (1) 1 hour ago"),
            try container("d", state: "running", status: "Up 1 hour"),
            try container("e", state: "running", status: "Up 1 hour"),
            try container("f", state: "running", status: "Up 1 hour (unhealthy)"),
        ]
        let after = [
            try container("a", state: "exited", status: "Exited (137) 2 seconds ago"),
            try container("b", state: "running", status: "Up 1 hour (unhealthy)"),
            try container("c", state: "exited", status: "Exited (1) 1 hour ago"),
            try container("d", state: "exited", status: "Exited (0) 2 seconds ago"),
            try container("e", state: "exited", status: "Exited (143) 2 seconds ago"),
            try container("f", state: "running", status: "Up 1 hour (unhealthy)"),
            try container("new", state: "exited", status: "Exited (1) 2 seconds ago"),
        ]
        let alerts = ContainerAlert.changes(from: before, to: after)
        #expect(alerts.map(\.containerID) == ["a", "b"])
        #expect(alerts.first?.kind == .exited(137))
        #expect(alerts.last?.kind == .unhealthy)
    }

    @Test func shellLauncherPinsColimaContextAndRemovesItself() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-shell-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = directory.appendingPathComponent("record")
        let docker = directory.appendingPathComponent("doc'ker")
        try Data(
            """
            #!/bin/sh
            printf '%s\\n' "$@" > \(record.path)
            printf 'host=%s\\n' "${DOCKER_HOST:-}" >> \(record.path)
            """.utf8
        ).write(to: docker)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: docker.path)

        let script = try ShellScript.write(ShellScript.container(docker: docker.path, id: "abc123"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.environment = ["DOCKER_HOST": "unix:///foreign.sock", "PATH": "/usr/bin:/bin"]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let lines = try String(contentsOf: record, encoding: .utf8).split(separator: "\n")
        #expect(Array(lines.prefix(6)) == ["--context", "colima", "exec", "-it", "abc123", "sh"])
        #expect(lines.last == "host=")
        #expect(!(FileManager.default.fileExists(atPath: script.path)))
        #expect(throws: (any Error).self) { try ShellScript.container(docker: docker.path, id: "abc; rm -rf ~") }
    }
}
