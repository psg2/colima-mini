import Foundation
import Testing

@testable import ColimaCore

struct InspectionTests {
    @Test func detailsKeepDatabaseProtocolAndSeparateNamedAndBindMounts() throws {
        let rows = try ContainerDetails.decode(InspectionRuntime.inspections)
        let database = try #require(rows.first { $0.id == "database" })
        #expect(database.state.health == "healthy")
        #expect(database.ports.first?.address == "127.0.0.1:5432")
        #expect(database.ports.first?.protocolName == "tcp")
        #expect(database.mounts.first?.name == "demo_db")
        #expect(database.mounts.first?.type == "volume")
        let worker = try #require(rows.first { $0.id == "worker" })
        #expect(worker.state.oomKilled == true)
        #expect(worker.state.exitCode == 137)
        #expect(worker.state.health == nil)
        #expect(worker.project == nil)
        #expect(worker.mounts[0].readOnly)
        #expect(rows.first { $0.id == "web" }?.mounts.first?.type == "bind")
    }

    @Test func missingHealthAndMountMetadataRemainUnavailable() throws {
        let row = try #require(
            ContainerDetails.decode(
                #"{"Id":"missing","Name":"/missing","Image":"sha256:unknown","Config":{"Image":"alpine","Labels":null},"State":{"Status":"created"}}"#
            ).first)
        #expect(row.state.oomKilled == nil)
        #expect(row.state.running == nil)
        #expect(row.state.health == nil)
        #expect(row.mountsAvailable == false)
        #expect(throws: (any Error).self) { try ContainerDetails.decode("unsupported inspection") }
    }

    @Test func imagesLinkContainersWithFullAndUnambiguousShortIDs() throws {
        let details = try ContainerDetails.decode(InspectionRuntime.inspections)
        let fullID = "sha256:" + String(repeating: "a", count: 64)
        #expect(
            DockerImage.referencingContainers(
                imageID: fullID, containers: details, knownImageIDs: [fullID]) == ["database", "worker"])
        #expect(
            DockerImage.referencingContainers(
                imageID: String(repeating: "a", count: 12), containers: details, knownImageIDs: [fullID]) == ["database", "worker"])
        let collision =
            "sha256:" + String(repeating: "a", count: 12) + String(repeating: "b", count: 52)
        #expect(
            DockerImage.referencingContainers(
                imageID: String(repeating: "a", count: 12), containers: details,
                knownImageIDs: [fullID, collision]) == nil)
    }

    @Test func sampleReadsDoNotRequireExecutables() async throws {
        let fixture = try SnapshotTests().fixture()
        let backend = Backend(
            fixture: fixture,
            toolchain: Toolchain(environment: [
                "COLIMA_MINI_DOCKER": "/nonexistent/docker", "COLIMA_MINI_COLIMA": "/nonexistent/colima",
            ]))
        let id = try #require(fixture.details?.keys.first)
        let details = try await backend.details(id)
        #expect(details.id == id)
        let volumes = try await backend.volumes()
        let images = try await backend.images()
        let storage = try await backend.storage()
        #expect(volumes.count == 3)
        #expect(images.count == 3)
        #expect(storage.filesystem != nil)
        do {
            _ = try await backend.details("removed")
            Issue.record("Removed sample has stale details")
        } catch { #expect(error.localizedDescription.contains("sample")) }
    }

    @Test func backendReferencesIncludeStoppedContainersAndUnknownMeasurements() async throws {
        try await InspectionRuntime.run { backend in
            let volumes = try await backend.volumes()
            let database = try #require(volumes.first { $0.name == "demo_db" })
            #expect(database.references.map(\.containerID) == ["database", "worker"])
            #expect(database.references.first { $0.containerID == "worker" }?.running == false)
            #expect(database.attached == true)
            #expect(database.sizeBytes == 1_976_000_000)
            let plugin = try #require(volumes.first { $0.name == "plugin_data" })
            #expect(plugin.sizeBytes == nil)
            #expect(plugin.attached == false)
            let details = try await backend.details("worker")
            #expect(details.state.oomKilled == true)
            let images = try await backend.images()
            #expect(images.first?.containerIDs == ["database", "worker"])
            #expect(images.first?.sharedBytes == 100_000_000)
            #expect(images.first?.uniqueBytes == 1_876_000_000)
        }
    }

    @Test func anonymousVolumesAreIdentifiedByDockerLabel() async throws {
        let anonymous = String(repeating: "c", count: 64)
        try await InspectionRuntime.run(overrides: [
            "volumeList":
                "{\"Name\":\"demo_db\",\"Driver\":\"local\"}\n{\"Name\":\"\(anonymous)\",\"Driver\":\"local\"}",
            "volumeMetadata":
                "{\"Name\":\"demo_db\",\"Driver\":\"local\",\"Labels\":{\"com.docker.compose.project\":\"demo\"}}\n{\"Name\":\"\(anonymous)\",\"Driver\":\"local\",\"Labels\":{\"com.docker.volume.anonymous\":\"\"}}",
        ]) { backend in
            let volumes = try await backend.volumes()
            #expect(volumes.first { $0.name == anonymous }?.anonymous == true)
            #expect(volumes.first { $0.name == "demo_db" }?.anonymous == false)
            #expect(volumes.first { $0.name == "demo_db" }?.project == "demo")
        }
    }

    @Test func failedReferenceReadNeverReportsVolumesAsUnattached() async throws {
        try await InspectionRuntime.run(overrides: ["inspectError": true]) { backend in
            let volumes = try await backend.volumes()
            #expect(volumes.allSatisfy { !$0.referencesAvailable && $0.attached == nil })
            #expect(volumes.allSatisfy { $0.dataIssue?.contains("reference") == true })
            #expect(volumes.first { $0.name == "demo_db" }?.sizeBytes == 1_976_000_000)
        }
    }
}

enum InspectionRuntime {
    static let inspections = """
        {"Id":"database","Name":"/demo-postgres-1","Image":"sha256:\(String(repeating: "a", count: 64))","Config":{"Image":"postgres:17","Labels":{"com.docker.compose.project":"demo","com.docker.compose.service":"postgres"}},"State":{"Status":"running","Running":true,"ExitCode":0,"OOMKilled":false,"Health":{"Status":"healthy"}},"RestartCount":0,"Mounts":[{"Type":"volume","Name":"demo_db","Source":"/var/lib/docker/volumes/demo_db/_data","Destination":"/var/lib/postgresql/data","RW":true}],"NetworkSettings":{"Ports":{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"5432"}],"80/tcp":null}}}
        {"Id":"worker","Name":"/worker","Image":"sha256:\(String(repeating: "a", count: 64))","Config":{"Image":"postgres:17","Labels":{"com.docker.compose.project":null}},"State":{"Status":"exited","Running":false,"ExitCode":137,"OOMKilled":true},"Mounts":[{"Type":"volume","Name":"demo_db","Source":"/var/lib/docker/volumes/demo_db/_data","Destination":"/backup/source","RW":false}]}
        {"Id":"web","Name":"/web","Image":"sha256:\(String(repeating: "b", count: 64))","Config":{"Image":"nginx:alpine"},"State":{"Status":"running","Running":true},"Mounts":[{"Type":"bind","Name":"demo_db","Source":"/tmp/demo_db","Destination":"/data","RW":true}]}
        """
    static func run(
        overrides: [String: Any] = [:], body: (Backend) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-inspection-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var state: [String: Any] = [
            "vm":
                #"{"name":"default","status":"Running","cpus":10,"memory":21474836480,"disk":107374182400}"#,
            "inspections": inspections,
            "dataRoot": "/var/lib/docker",
            "volumeList":
                "{\"Name\":\"demo_db\",\"Driver\":\"local\"}\n{\"Name\":\"plugin_data\",\"Driver\":\"plugin\"}",
            "volumeMetadata":
                "{\"Name\":\"demo_db\",\"Driver\":\"local\",\"Labels\":{\"com.docker.compose.project\":\"demo\"}}\n{\"Name\":\"plugin_data\",\"Driver\":\"plugin\",\"Labels\":null}",
            "verbose":
                "{\"Images\":[{\"ID\":\"sha256:\(String(repeating: "a", count: 64))\",\"Repository\":\"postgres\",\"Tag\":\"17\",\"Size\":\"1.976GB\",\"SharedSize\":\"100MB\",\"UniqueSize\":\"1.876GB\"}],\"Volumes\":[{\"Name\":\"demo_db\",\"Size\":\"1.976GB\"},{\"Name\":\"plugin_data\",\"Size\":\"N/A\"}]}",
            "summary":
                #"{"Type":"Images","TotalCount":"1","Active":"1","Size":"1.976GB","Reclaimable":"100MB (5%)"}"#,
            "filesystem":
                "Filesystem 1B-blocks Used Available Use% Mounted on\n/dev/vdb1 100000000000 20000000000 75000000000 20% /var/lib/docker\n",
        ]
        state.merge(overrides, uniquingKeysWith: { _, new in new })
        // One file per state key; a `true` switch is an empty file.
        let stateDirectory = directory.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        for (key, value) in state {
            if let text = value as? String {
                try Data((text + "\n").utf8).write(to: stateDirectory.appendingPathComponent(key))
            } else if value as? Bool == true {
                try Data().write(to: stateDirectory.appendingPathComponent(key))
            }
        }
        let program = #"""
            #!/bin/sh
            d="$COLIMA_INSPECTION_STATE"
            fail() { echo "$1" >&2; exit 1; }
            if [ "$(basename "$0")" = colima ]; then
              case "$1" in
                list) cat "$d/vm" ;;
                ssh)
                  eval "last=\${$#}"
                  if [ -f "$d/filesystemError" ] || [ "$last" != "$(cat "$d/dataRoot")" ]; then
                    fail 'data filesystem unavailable'
                  fi
                  cat "$d/filesystem" ;;
                *) fail 'unsupported Colima read' ;;
              esac
              exit 0
            fi
            if [ "$1 $2" != "--context colima" ] || [ -n "${DOCKER_HOST+set}" ]; then fail 'foreign Docker runtime'; fi
            shift 2
            # Each inspection line starts with {"Id":"<id>".
            id_of() { sed -n 's/^{"Id":"\([^"]*\)".*/\1/p'; }
            case "$1 $2" in
              info*) cat "$d/dataRoot" ;;
              ps*) id_of <"$d/inspections" ;;
              inspect*)
                [ ! -f "$d/inspectError" ] || fail 'container references unavailable'
                shift
                while IFS= read -r line; do
                  id=$(printf '%s\n' "$line" | id_of)
                  for wanted in "$@"; do
                    if [ "$wanted" = "$id" ]; then printf '%s\n' "$line"; break; fi
                  done
                done <"$d/inspections" ;;
              "volume ls") cat "$d/volumeList" ;;
              "volume inspect") cat "$d/volumeMetadata" ;;
              "system df")
                [ ! -f "$d/dockerError" ] || fail 'daemon accounting unavailable'
                case " $* " in
                  *" --verbose "*) cat "$d/verbose" ;;
                  *) cat "$d/summary" ;;
                esac ;;
              *) fail 'unsupported Docker read' ;;
            esac
            """#
        for name in ["docker", "colima"] {
            let url = directory.appendingPathComponent(name)
            try Data((program + "\n").utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        var env = ProcessInfo.processInfo.environment
        env["COLIMA_MINI_DOCKER"] = directory.appendingPathComponent("docker").path
        env["COLIMA_MINI_COLIMA"] = directory.appendingPathComponent("colima").path
        env["COLIMA_HOME"] = directory.appendingPathComponent("unsupported-home").path
        env["COLIMA_INSPECTION_STATE"] = stateDirectory.path
        env["DOCKER_HOST"] = "unix:///foreign.sock"
        try await body(Backend(toolchain: Toolchain(environment: env)))
    }
}
