import Foundation
import XCTest

@testable import ColimaCore

final class NetworkTests: XCTestCase {
    private func run(body: (Backend, () throws -> [String]) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-networks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = directory.appendingPathComponent("commands")
        // Network IDs in `docker network ls` order, each served by `inspect`.
        let networks: [(String, String)] = [
            (
                "id-bridge",
                #"{"Id":"id-bridge","Name":"bridge","Driver":"bridge","IPAM":{"Config":[{"Subnet":"172.17.0.0/16"}]},"Containers":{}}"#
            ),
            (
                "id-app",
                #"{"Id":"id-app","Name":"app_default","Driver":"bridge","IPAM":{"Config":[{"Subnet":"172.19.0.0/16","Gateway":"172.19.0.1"}]},"Containers":{"c2":{"Name":"app-web-1","IPv4Address":"172.19.0.3/16"},"c1":{"Name":"app-db-1","IPv4Address":""}},"Labels":{"com.docker.compose.project":"app"}}"#
            ),
            (
                "id-old",
                #"{"Id":"id-old","Name":"old_default","Driver":"bridge","IPAM":{"Config":null},"Containers":null,"Labels":null}"#
            ),
        ]
        let networkDirectory = directory.appendingPathComponent("networks")
        try FileManager.default.createDirectory(at: networkDirectory, withIntermediateDirectories: true)
        for (id, json) in networks { try Data(json.utf8).write(to: networkDirectory.appendingPathComponent(id)) }
        try Data((networks.map(\.0).joined(separator: "\n") + "\n").utf8).write(
            to: directory.appendingPathComponent("network-ids"))
        let program = #"""
            #!/bin/sh
            [ "$1 $2" = "--context colima" ] || { echo 'foreign Docker runtime' >&2; exit 1; }
            shift 2
            case "$1 $2" in
              "network ls") cat "$NETWORK_STATE/network-ids" ;;
              "network inspect")
                shift 2
                printf '['
                separator=''
                for id in "$@"; do printf '%s' "$separator"; cat "$NETWORK_STATE/networks/$id"; separator=','; done
                echo ']' ;;
              *) echo "$*" >>"$NETWORK_RECORD" ;;
            esac
            """#
        let docker = directory.appendingPathComponent("docker")
        try Data((program + "\n").utf8).write(to: docker)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: docker.path)
        var env = ProcessInfo.processInfo.environment
        env["COLIMA_MINI_DOCKER"] = docker.path
        env["NETWORK_RECORD"] = record.path
        env["NETWORK_STATE"] = directory.path
        try await body(Backend(toolchain: Toolchain(environment: env))) {
            guard FileManager.default.fileExists(atPath: record.path) else { return [] }
            return try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init)
        }
    }

    func testNetworksListMembersProjectsAndSubnetsWithBuiltInsLast() async throws {
        try await run { backend, _ in
            let networks = try await backend.networks()
            XCTAssertEqual(networks.map(\.name), ["app_default", "old_default", "bridge"])
            let app = networks[0]
            XCTAssertEqual(app.project, "app")
            XCTAssertEqual(app.subnets, ["172.19.0.0/16"])
            XCTAssertEqual(
                app.members,
                [
                    DockerNetwork.Member(id: "c1", name: "app-db-1", address: nil),
                    DockerNetwork.Member(id: "c2", name: "app-web-1", address: "172.19.0.3/16"),
                ])
            XCTAssertEqual(networks[1].members, [])
            XCTAssertTrue(networks[2].builtin)
        }
    }

    func testRemovalNeverForcesAndRefusesBuiltIns() async throws {
        try await run { backend, commands in
            let networks = try await backend.networks()
            try await backend.removeNetwork(networks[1])
            do {
                try await backend.removeNetwork(networks[2])
                XCTFail("Removed a built-in network")
            } catch {}
            XCTAssertEqual(try commands(), ["network rm id-old"])
        }
    }
}
