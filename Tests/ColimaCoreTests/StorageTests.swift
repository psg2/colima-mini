import Foundation
import Testing

@testable import ColimaCore

struct StorageTests {
    @Test func diskMeasurementsDistinguishDecimalBinaryAndUnknown() {
        #expect(DiskBytes.parse("1.976GB") == 1_976_000_000)
        #expect(DiskBytes.parse("1.5GiB") == 1_610_612_736)
        #expect(DiskBytes.parse("93.01MB (41%)") == 93_010_000)
        #expect(DiskBytes.parse("0B") == 0)
        #expect(DiskBytes.parse("Unknown") == nil)
        #expect(DiskBytes.parse("-1GB") == nil)
        #expect(DiskBytes.parse("NaNGB") == nil)
    }

    @Test func dataFilesystemReservedSpaceIsNotCalledUsed() throws {
        let fs = try FilesystemUsage.decode(
            "Filesystem 1B-blocks Used Available Use% Mounted on\n/dev/vdb1 1000 100 800 10% /var/lib/docker\n"
        )
        #expect(fs.sizeBytes == 1000)
        #expect(fs.usedBytes == 100)
        #expect(fs.availableBytes == 800)
        #expect(fs.reservedBytes == 100)
        #expect(fs.mountpoint == "/var/lib/docker")
        #expect(throws: (any Error).self) { try FilesystemUsage.decode("Filesystem\n/dev/vdb1 1000 1000 800 10% /") }
        #expect(throws: (any Error).self) { try FilesystemUsage.decode("Filesystem\n/dev/vdb1 unknown 100 800 10% /") }
    }

    @Test func lowDiskWarnsBelowATenthOrThreeGiB() throws {
        func usage(size: Int64, available: Int64) throws -> FilesystemUsage {
            try FilesystemUsage.decode(
                "Filesystem 1B-blocks Used Available Use% Mounted on\n/dev/vdb1 \(size) \(size - available) \(available) 0% /var/lib/docker\n"
            )
        }
        let gib: Int64 = 1 << 30
        #expect(!(try usage(size: 100 * gib, available: 79 * gib).isLow))
        #expect(try usage(size: 100 * gib, available: 9 * gib).isLow)
        #expect(!(try usage(size: 20 * gib, available: 4 * gib).isLow))
        #expect(try usage(size: 20 * gib, available: 2 * gib).isLow)
    }

    @Test func unsupportedAccountingFailsInsteadOfInventingZeros() throws {
        #expect(throws: (any Error).self) { try DockerStorageCategory.decode("") }
        #expect(throws: (any Error).self) {
            try DockerStorageCategory.decode(
                #"{"Type":"Images","Size":"N/A","Reclaimable":"0B","TotalCount":"1","Active":"0"}"#)
        }
        let rows = try DockerStorageCategory.decode(
            #"{"Type":"Images","Size":"1.976GB","Reclaimable":"100MB (5%)","TotalCount":"3","Active":"2"}"#
        )
        #expect(rows.first?.sizeBytes == 1_976_000_000)
        #expect(rows.first?.reclaimableBytes == 100_000_000)
    }

    @Test func missingOptionalFixtureInventoryAndDiskRemainCompatible() throws {
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(
                #"{"vm":"{\"name\":\"default\",\"status\":\"Stopped\",\"cpus\":2,\"memory\":2147483648}","containers":"","stats":""}"#
                    .utf8))
        #expect(try fixture.snapshot.vm.disk == nil)
        #expect(fixture.details == nil)
        #expect(fixture.volumes == nil)
        #expect(fixture.storage == nil)
    }

    @Test func storageSectionsFailIndependently() async throws {
        try await InspectionRuntime.run(overrides: ["filesystemError": true]) { backend in
            let storage = try await backend.storage()
            #expect(storage.configuredCapacityBytes == 107_374_182_400)
            #expect(storage.filesystem == nil)
            #expect(storage.errors["filesystem"] != nil)
            #expect(storage.docker.first?.sizeBytes == 1_976_000_000)
            #expect(storage.errors["docker"] == nil)
            #expect(storage.hostAllocatedBytes == nil)
            #expect(storage.errors["host"] != nil)
        }
        try await InspectionRuntime.run(overrides: ["dockerError": true]) { backend in
            let storage = try await backend.storage()
            #expect(storage.filesystem?.usedBytes == 20_000_000_000)
            #expect(storage.docker.isEmpty)
            #expect(storage.errors["docker"] != nil)
        }
    }

    @Test func unsupportedDataRootIsUnavailableRatherThanPassedToSSH() async throws {
        try await InspectionRuntime.run(overrides: ["dataRoot": "/srv/docker data; invalid"]) {
            backend in
            let storage = try await backend.storage()
            #expect(storage.filesystem == nil)
            #expect(storage.errors["filesystem"]?.contains("usable data filesystem path") == true)
            #expect(!storage.docker.isEmpty)
        }
    }

    @Test func customDockerDataRootMeasuresItsOwnFilesystem() async throws {
        try await InspectionRuntime.run(overrides: [
            "dataRoot": "/srv/docker-data",
            "filesystem":
                "Filesystem 1B-blocks Used Available Use% Mounted on\n/dev/vdc1 1000 100 800 10% /srv/docker-data\n",
        ]) { backend in
            let storage = try await backend.storage()
            #expect(storage.filesystem?.mountpoint == "/srv/docker-data")
            #expect(storage.filesystem?.usedBytes == 100)
            #expect(storage.errors["filesystem"] == nil)
        }
    }

    @Test func stoppedVMReportsCapacityAndUnavailableRuntimeMeasurements() async throws {
        try await InspectionRuntime.run(overrides: [
            "vm":
                #"{"name":"default","status":"Stopped","cpus":10,"memory":21474836480,"disk":107374182400}"#
        ]) { backend in
            let storage = try await backend.storage()
            #expect(storage.configuredCapacityBytes == 107_374_182_400)
            #expect(storage.filesystem == nil)
            #expect(storage.docker.isEmpty)
            #expect(storage.errors["docker"]?.contains("Start Colima") == true)
        }
    }

    @Test func sparseImagesMeasureAllocationAndUnsupportedLayoutsStayUnknown() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(
            "colima-sparse-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let lima = home.appendingPathComponent("_lima")
        try FileManager.default.createDirectory(
            at: lima.appendingPathComponent("colima"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: lima.appendingPathComponent("_disks/colima"), withIntermediateDirectories: true)
        let config = lima.appendingPathComponent("colima/lima.yaml")
        try Data("vmType: vz\nadditionalDisks:\n    - name: colima\n      format: false\n".utf8).write(
            to: config)
        for path in ["colima/disk", "_disks/colima/datadisk"] {
            let url = lima.appendingPathComponent(path)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let file = try FileHandle(forWritingTo: url)
            try file.truncate(atOffset: 1_073_741_824)
            try file.write(contentsOf: Data("sample".utf8))
            try file.close()
        }
        let allocation = try HostDiskFootprint.allocatedBytes(home: home)
        #expect(allocation > 0)
        #expect(allocation < 2_147_483_648)
        try Data("vmType: qemu\n".utf8).write(to: config)
        #expect(throws: (any Error).self) { try HostDiskFootprint.allocatedBytes(home: home) }
    }
}
