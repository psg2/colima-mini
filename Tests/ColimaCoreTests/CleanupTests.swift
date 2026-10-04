import Foundation
import XCTest

@testable import ColimaCore

final class CleanupTests: XCTestCase {
    private static let accounting: [String: Any] = [
        "Containers": [
            [
                "ID": "running1", "Names": "demo-postgres-1", "Image": "postgres:18",
                "State": "running", "Status": "Up 1 hour", "Size": "20kB",
            ],
            [
                "ID": "stopped1", "Names": "demo-worker-1", "Image": "worker:latest",
                "State": "exited", "Status": "Exited (0) 2 days ago", "Size": "1MB",
            ],
        ],
        "Images": [
            [
                "ID": "sha256:used", "Repository": "postgres", "Tag": "18", "Containers": "1",
                "Size": "600MB", "UniqueSize": "600MB",
            ],
            [
                "ID": "sha256:abcdef1234567890", "Repository": "<none>", "Tag": "<none>",
                "Containers": "0", "Size": "300MB", "UniqueSize": "200MB",
            ],
            [
                "ID": "sha256:redis", "Repository": "redis", "Tag": "7-alpine", "Containers": "0",
                "Size": "56MB", "UniqueSize": "56MB",
            ],
        ],
        "Volumes": [
            [
                "Name": "demo_db", "Labels": "com.docker.compose.project=demo", "Links": "0", "Size": "2GB",
            ],
            ["Name": "anon1", "Labels": "com.docker.volume.anonymous=", "Links": "0", "Size": "10MB"],
            ["Name": "anon2", "Labels": "com.docker.volume.anonymous=", "Links": "0", "Size": "5MB"],
            ["Name": "anon3", "Labels": "com.docker.volume.anonymous=", "Links": "1", "Size": "7MB"],
        ],
        "BuildCache": [
            ["ID": "cache1", "InUse": "false", "Size": "90MB", "Description": "pulled nginx"],
            ["ID": "cache2", "InUse": "true", "Size": "5MB"],
            ["ID": "cache3", "InUse": "false", "Shared": "true", "Size": "30MB"],
        ],
    ]

    private func run(body: (Backend, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-cleanup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = directory.appendingPathComponent("df.json")
        try JSONSerialization.data(withJSONObject: Self.accounting).write(to: state)
        let record = directory.appendingPathComponent("commands")
        let program = #"""
            #!/bin/sh
            [ "$1 $2" = "--context colima" ] || { echo 'foreign Docker runtime' >&2; exit 1; }
            shift 2
            case "$1 $2" in
              "system df") cat "$CLEANUP_DF"; echo ;;
              "network ls") echo '{"ID":"net1","Name":"old_default","Driver":"bridge"}' ;;
              *)
                echo "$*" >>"$CLEANUP_RECORD"
                if [ "$*" = "volume rm anon2" ]; then echo 'Error: volume is in use' >&2; exit 1; fi
                if [ "$1 $2" = "builder prune" ]; then
                  printf 'ID\tRECLAIMABLE\tSIZE\ncache1\ttrue\t90MB\nTotal:\t94.37MB\n'
                fi ;;
            esac
            """#
        let docker = directory.appendingPathComponent("docker")
        try Data((program + "\n").utf8).write(to: docker)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: docker.path)
        var env = ProcessInfo.processInfo.environment
        env["COLIMA_MINI_DOCKER"] = docker.path
        env["CLEANUP_DF"] = state.path
        env["CLEANUP_RECORD"] = record.path
        try await body(Backend(toolchain: Toolchain(environment: env)), record)
    }

    func testPlanListsOnlyUnreferencedObjectsAndNeverNamedVolumes() async throws {
        try await run { backend, _ in
            let plan = try await backend.cleanupPlan()
            func ids(_ kind: CleanupKind) -> [String] { plan.category(kind)?.items.map(\.id) ?? [] }
            XCTAssertEqual(ids(.stoppedContainers), ["stopped1"])
            XCTAssertEqual(ids(.danglingImages), ["sha256:abcdef1234567890"])
            XCTAssertEqual(ids(.unusedImages), ["redis:7-alpine"])
            XCTAssertEqual(ids(.buildCache), ["cache1"])
            XCTAssertEqual(ids(.networks), ["net1"])
            XCTAssertEqual(ids(.anonymousVolumes), ["anon1", "anon2"])
            XCTAssertFalse(plan.categories.flatMap(\.items).contains { $0.id == "demo_db" })
            XCTAssertEqual(plan.category(.danglingImages)?.bytes, 200_000_000)
        }
    }

    func testReclaimRemovesOnlyPreviewedItemsOfSelectedKindsAndReportsRefusals() async throws {
        try await run { backend, record in
            let plan = try await backend.cleanupPlan()
            let result = try await backend.reclaim(
                plan, kinds: [.danglingImages, .anonymousVolumes, .buildCache])
            let commands = try String(contentsOf: record, encoding: .utf8)
                .split(separator: "\n").map(String.init)
            XCTAssertEqual(
                commands,
                [
                    "image rm sha256:abcdef1234567890", "builder prune --force", "volume rm anon1",
                    "volume rm anon2",
                ])
            XCTAssertEqual(result.removed[.danglingImages], 1)
            XCTAssertEqual(result.removed[.anonymousVolumes], 1)
            XCTAssertEqual(result.failures.count, 1)
            XCTAssertTrue(result.failures[0].contains("in use"))
            XCTAssertEqual(result.reclaimedBytes, 200_000_000 + 94_370_000 + 10_000_000, accuracy: 1)
        }
    }

    func testSampleModeNeverPlansOrRemoves() async throws {
        let backend = Backend(fixture: try SnapshotTests().fixture())
        do {
            _ = try await backend.cleanupPlan()
            XCTFail("Sample mode produced a cleanup plan")
        } catch {}
        let plan = CleanupPlan(
            measuredAt: Date(),
            categories: [
                CleanupCategory(
                    kind: .danglingImages, items: [CleanupItem(id: "x", name: "x", detail: "", bytes: 1)])
            ])
        do {
            _ = try await backend.reclaim(plan, kinds: [.danglingImages])
            XCTFail("Sample mode removed objects")
        } catch {}
    }
}
