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

extension DockerImage {
    // The reference Docker should act on: the tag, or the ID for an untagged image.
    package var reference: String {
        repository == "<none>" || tag == "<none>" ? imageID : name
    }
    package var unused: Bool { referencesAvailable && containerIDs.isEmpty }
}

extension Backend {
    // Untags, and deletes the image once no tag is left. Without --force, Docker
    // refuses an image any container, running or stopped, still uses.
    package func removeImage(_ image: DockerImage) async throws {
        _ = try await docker(["image", "rm", image.reference], timeout: 60)
    }
    package func pullImage(_ image: DockerImage) async throws {
        guard image.reference == image.name else {
            throw AppError.message("An untagged image has nothing to pull.")
        }
        _ = try await docker(["pull", "--quiet", image.name], timeout: 600)
    }
}
