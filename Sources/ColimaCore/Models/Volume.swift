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
