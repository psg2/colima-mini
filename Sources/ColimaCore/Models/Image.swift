import Foundation

package struct DockerImage: Codable, Identifiable {
  package let imageID: String
  package let repository: String
  package let tag: String
  package let sizeBytes: Double?
  package let sharedBytes: Double?
  package let uniqueBytes: Double?
  package let containerIDs: [String]
  package let referencesAvailable: Bool
  package var id: String { "\(imageID):\(repository):\(tag)" }
  package var name: String { "\(repository):\(tag)" }

  package static func referencingContainers(
    imageID: String, containers: [ContainerDetails], knownImageIDs: [String]
  ) -> [String]? {
    func canonical(_ value: String) -> String {
      value.hasPrefix("sha256:") ? String(value.dropFirst(7)) : value
    }
    let reported = canonical(imageID)
    guard reported.count >= 12, reported.count <= 64,
      reported.allSatisfy({ $0.isHexDigit })
    else { return nil }
    let fullIDs = Set(
      (knownImageIDs + containers.map(\.imageID)).map(canonical).filter { $0.count == 64 })
    let matches = fullIDs.filter { $0.hasPrefix(reported) }
    guard matches.count == 1, let full = matches.first else { return nil }
    return containers.filter { canonical($0.imageID) == full }.map(\.id).sorted()
  }
}
