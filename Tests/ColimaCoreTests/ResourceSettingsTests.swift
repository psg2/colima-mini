import Foundation
import Testing

@testable import ColimaCore

struct ResourceSettingsTests {
    let original = """
        # Local resources
        cpu: 2 # Keep this comment
        memory: 4.5
        disk: 100
        vmType: vz
        mounts:
          - location: /tmp/project
            writable: true
        nested:
          cpu: 99
          memory: 88

        """
    func withConfig(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("colima.yaml")
        try Data(original.utf8).write(to: config)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        try body(config)
    }
    @Test func fractionalRAMAndPreservationOfOtherConfiguration() throws {
        try withConfig { config in
            #expect(try ResourceSettings.read(from: config) == ResourceSettings(cpus: 2, memoryGiB: 4.5, diskGiB: 100))
            let desired = ResourceSettings(cpus: 2, memoryGiB: 2.5, diskGiB: 100)
            try desired.save(to: config)
            #expect(try ResourceSettings.read(from: config) == desired)
            let expected = original.replacingOccurrences(of: "memory: 4.5", with: "memory: 2.5")
            #expect(try String(contentsOf: config, encoding: .utf8) == expected)
            let permissions =
                try FileManager.default.attributesOfItem(atPath: config.path)[.posixPermissions]
                as? NSNumber
            #expect(permissions?.intValue == 0o600)
            let backup = config.deletingLastPathComponent().appendingPathComponent(
                "colima.yaml.mini-backup")
            #expect(try String(contentsOf: backup, encoding: .utf8) == original)
            try ResourceSettings(cpus: 1, memoryGiB: 1.5).save(to: config)
            #expect(try String(contentsOf: backup, encoding: .utf8) == original)
        }
    }
    @Test func diskGrowsButNeverShrinks() throws {
        try withConfig { config in
            try ResourceSettings(cpus: 2, memoryGiB: 4.5, diskGiB: 160).save(to: config)
            #expect(try ResourceSettings.read(from: config).diskGiB == 160)
            let grown = try String(contentsOf: config, encoding: .utf8)
            #expect(grown == original.replacingOccurrences(of: "disk: 100", with: "disk: 160"))
            #expect(throws: (any Error).self) { try ResourceSettings(cpus: 2, memoryGiB: 4.5, diskGiB: 120).save(to: config) }
            #expect(try String(contentsOf: config, encoding: .utf8) == grown)
            // Leaving the disk out keeps the configured size.
            try ResourceSettings(cpus: 1, memoryGiB: 4.5).save(to: config)
            #expect(try ResourceSettings.read(from: config).diskGiB == 160)
        }
    }
    @Test func outOfRangeAndNonfiniteAllocationsLeaveFileUntouched() throws {
        try withConfig { config in
            for invalid in [
                ResourceSettings(cpus: 0, memoryGiB: 2),
                ResourceSettings(cpus: ResourceSettings.hostCPUs + 1, memoryGiB: 2),
                ResourceSettings(cpus: 1, memoryGiB: Double(ResourceSettings.hostMemory) + 1),
                ResourceSettings(cpus: 1, memoryGiB: .nan),
            ] {
                #expect(throws: (any Error).self) { try invalid.save(to: config) }
                let contents = try String(contentsOf: config, encoding: .utf8)
                #expect(contents == original)
            }
        }
    }
    @Test func malformedRootFieldsAreRejectedWithoutOverwrite() throws {
        try withConfig { config in
            for malformed in [
                "cpu: 2\nmemory: 4\ncpu: 5\n", "cpu: 2\nnested:\n  memory: 4\n",
                "cpu: 1.5\nmemory: 4\n", "cpu: 999999999999999999999999\nmemory: 4\n",
            ] {
                try Data(malformed.utf8).write(to: config)
                #expect(throws: (any Error).self) { try ResourceSettings(cpus: 1, memoryGiB: 2).save(to: config) }
                #expect(try String(contentsOf: config, encoding: .utf8) == malformed)
            }
        }
    }
}
