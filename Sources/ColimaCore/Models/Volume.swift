import Foundation

package struct VolumeReference: Codable, Identifiable {
    package let containerID: String
    package let containerName: String
    package let destination: String
    package let readOnly: Bool
    package let running: Bool
    package var id: String { "\(containerID):\(destination)" }
}

package struct Volume: Codable, Identifiable {
    package let name: String
    package let driver: String
    package let project: String?
    package let mountpoint: String?
    package let createdAt: String?
    package let sizeBytes: Double?
    package let references: [VolumeReference]
    package let referencesAvailable: Bool
    package let dataIssue: String?
    // Docker labels volumes it creates for unnamed mounts; nil when metadata is unavailable.
    package var anonymous: Bool? = nil
    package var id: String { name }
    package var attached: Bool? { referencesAvailable ? !references.isEmpty : nil }
}

extension Backend {
    // Deletes the volume and its data. Without --force, Docker refuses a volume
    // that any container, running or stopped, still references.
    package func removeVolume(_ name: String) async throws {
        guard !name.isEmpty, !name.hasPrefix("-") else {
            throw AppError.message("The volume name is invalid.")
        }
        _ = try await docker(["volume", "rm", name], timeout: 60)
    }
}
