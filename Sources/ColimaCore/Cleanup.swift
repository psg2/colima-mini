import Foundation

// Reclaiming space is a preview followed by removal of exactly what the preview
// listed. Removal targets individual IDs without --force, so Docker itself refuses
// anything that started running or gained a reference after the preview.
// Named volumes are never candidates.
package enum CleanupKind: String, CaseIterable, Codable, Identifiable {
  case stoppedContainers, danglingImages, unusedImages, buildCache, networks, anonymousVolumes
  package var id: String { rawValue }
  // Selected by default: removal loses nothing that can't be rebuilt or re-pulled.
  package var safeByDefault: Bool {
    switch self {
    case .danglingImages, .buildCache, .networks: return true
    case .stoppedContainers, .unusedImages, .anonymousVolumes: return false
    }
  }
  package var title: String {
    switch self {
    case .stoppedContainers: return "Stopped containers"
    case .danglingImages: return "Dangling images"
    case .unusedImages: return "Unused images"
    case .buildCache: return "Build cache"
    case .networks: return "Unused networks"
    case .anonymousVolumes: return "Unattached anonymous volumes"
    }
  }
  package var explanation: String {
    switch self {
    case .stoppedContainers:
      return
        "Their volumes are kept. Compose recreates them on the next up, but logs and container files are lost."
    case .danglingImages: return "Untagged layers left behind by rebuilds and pulls."
    case .unusedImages:
      return
        "Tagged images no container uses, including stopped ones. They download again when needed."
    case .buildCache: return "Cache Docker isn't using. Later builds may take longer."
    case .networks: return "Custom networks without containers. Compose recreates its own."
    case .anonymousVolumes:
      return
        "Volumes Docker created for unnamed mounts, now without any container. Their data is deleted."
    }
  }
}

package struct CleanupItem: Codable, Identifiable, Equatable {
  // The argument passed to the removal command.
  package let id: String
  package let name: String
  package let detail: String
  package let bytes: Double?
}

package struct CleanupCategory: Codable, Identifiable {
  package let kind: CleanupKind
  package let items: [CleanupItem]
  package var id: CleanupKind { kind }
  package var bytes: Double { items.compactMap(\.bytes).reduce(0, +) }
}

package struct CleanupPlan: Codable {
  package let measuredAt: Date
  package let categories: [CleanupCategory]
  package func category(_ kind: CleanupKind) -> CleanupCategory? {
    categories.first { $0.kind == kind }
  }
  package var isEmpty: Bool { categories.allSatisfy(\.items.isEmpty) }
}

package struct CleanupResult {
  package let removed: [CleanupKind: Int]
  package let reclaimedBytes: Double
  package let failures: [String]
  package var removedCount: Int { removed.values.reduce(0, +) }
}

extension Backend {
  package func cleanupPlan() async throws -> CleanupPlan {
    guard fixture == nil else {
      throw AppError.message("Reclaiming space is disabled in sample mode.")
    }
    async let usageOutput = docker(
      ["system", "df", "--verbose", "--format", "{{json .}}"], timeout: 45)
    async let networkOutput = docker([
      "network", "ls", "--filter", "dangling=true", "--format", "{{json .}}",
    ])
    let usage = try JSONDecoder().decode(
      CleanupAccounting.self, from: Data(try await usageOutput.utf8))
    let networks = try Snapshot.lines(try await networkOutput, as: NetworkRow.self)
    return CleanupPlan(measuredAt: Date(), categories: usage.categories(networks: networks))
  }

  package func reclaim(_ plan: CleanupPlan, kinds: Set<CleanupKind>) async throws -> CleanupResult {
    guard fixture == nil else {
      throw AppError.message("Reclaiming space is disabled in sample mode.")
    }
    var removed: [CleanupKind: Int] = [:]
    var reclaimed = 0.0
    var failures: [String] = []
    // Containers go first so a later pass can see what they released.
    for kind in CleanupKind.allCases where kinds.contains(kind) {
      guard let category = plan.category(kind), !category.items.isEmpty else { continue }
      try Task.checkCancellation()
      if kind == .buildCache {
        do {
          let output = try await docker(["builder", "prune", "--force"], timeout: 120)
          removed[kind] = category.items.count
          reclaimed += Self.reclaimedTotal(output) ?? category.bytes
        } catch { failures.append("Build cache: " + error.localizedDescription) }
        continue
      }
      for item in category.items {
        try Task.checkCancellation()
        do {
          _ = try await docker(Self.removal(kind) + [item.id], timeout: 60)
          removed[kind, default: 0] += 1
          reclaimed += item.bytes ?? 0
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          failures.append(item.name + ": " + error.localizedDescription)
        }
      }
    }
    return CleanupResult(removed: removed, reclaimedBytes: reclaimed, failures: failures)
  }

  private static func removal(_ kind: CleanupKind) -> [String] {
    switch kind {
    case .stoppedContainers: return ["container", "rm"]
    case .danglingImages, .unusedImages: return ["image", "rm"]
    case .networks: return ["network", "rm"]
    case .anonymousVolumes: return ["volume", "rm"]
    case .buildCache: return ["builder", "prune", "--force"]
    }
  }

  static func reclaimedTotal(_ output: String) -> Double? {
    output.split(whereSeparator: \.isNewline).last { $0.hasPrefix("Total") }
      .flatMap { $0.split(separator: ":").last }.flatMap { DiskBytes.parse(String($0)) }
  }
}

private struct NetworkRow: Decodable {
  let id: String
  let name: String
  let driver: String
  enum CodingKeys: String, CodingKey {
    case id = "ID"
    case name = "Name"
    case driver = "Driver"
  }
}

private struct CleanupAccounting: Decodable {
  let images: [Image]?
  let containers: [Container]?
  let volumes: [Volume]?
  let buildCache: [Cache]?
  enum CodingKeys: String, CodingKey {
    case images = "Images"
    case containers = "Containers"
    case volumes = "Volumes"
    case buildCache = "BuildCache"
  }
  struct Image: Decodable {
    let id: String
    let repository: String
    let tag: String
    let containers: String
    let size: String
    let uniqueSize: String?
    enum CodingKeys: String, CodingKey {
      case id = "ID"
      case repository = "Repository"
      case tag = "Tag"
      case containers = "Containers"
      case size = "Size"
      case uniqueSize = "UniqueSize"
    }
  }
  struct Container: Decodable {
    let id: String
    let names: String
    let image: String
    let state: String
    let status: String
    let size: String?
    enum CodingKeys: String, CodingKey {
      case id = "ID"
      case names = "Names"
      case image = "Image"
      case state = "State"
      case status = "Status"
      case size = "Size"
    }
  }
  struct Volume: Decodable {
    let name: String
    let labels: String
    let links: String
    let size: String
    enum CodingKeys: String, CodingKey {
      case name = "Name"
      case labels = "Labels"
      case links = "Links"
      case size = "Size"
    }
  }
  struct Cache: Decodable {
    let id: String
    let inUse: String
    let size: String
    let description: String?
    let shared: String?
    enum CodingKeys: String, CodingKey {
      case id = "ID"
      case inUse = "InUse"
      case shared = "Shared"
      case size = "Size"
      case description = "Description"
    }
  }

  func categories(networks: [NetworkRow]) -> [CleanupCategory] {
    let stopped = (containers ?? []).filter {
      !["running", "paused", "restarting"].contains($0.state)
    }
    .map {
      CleanupItem(
        id: $0.id, name: $0.names, detail: $0.image + " · " + $0.status,
        bytes: $0.size.flatMap { DiskBytes.parse($0) })
    }
    let unused = (images ?? []).filter { $0.containers == "0" }
    // A dangling image has no tag, so it can only be removed by ID. Tagged images
    // are removed by name: an ID shared by several tags would be refused.
    let dangling = unused.filter { $0.repository == "<none>" }.map {
      CleanupItem(
        id: $0.id, name: String($0.id.replacingOccurrences(of: "sha256:", with: "").prefix(12)),
        detail: "Untagged", bytes: DiskBytes.parse($0.uniqueSize ?? $0.size))
    }
    let tagged = unused.filter { $0.repository != "<none>" && $0.tag != "<none>" }.map {
      CleanupItem(
        id: "\($0.repository):\($0.tag)", name: "\($0.repository):\($0.tag)",
        detail: "Not used by any container", bytes: DiskBytes.parse($0.uniqueSize ?? $0.size))
    }
    // Shared records hold layers that images still use, so prune keeps them.
    let cache = (buildCache ?? []).filter { $0.inUse == "false" && $0.shared != "true" }.map {
      CleanupItem(
        id: $0.id, name: $0.description ?? $0.id, detail: "Build cache record",
        bytes: DiskBytes.parse($0.size))
    }
    let anonymous = (volumes ?? []).filter {
      $0.links == "0"
        && $0.labels.split(separator: ",").contains { $0.hasPrefix("com.docker.volume.anonymous=") }
    }.map {
      CleanupItem(
        id: $0.name, name: String($0.name.prefix(12)), detail: "Anonymous, no containers",
        bytes: DiskBytes.parse($0.size))
    }
    let unusedNetworks = networks.map {
      CleanupItem(id: $0.id, name: $0.name, detail: $0.driver + " network", bytes: nil)
    }
    let groups: [CleanupKind: [CleanupItem]] = [
      .stoppedContainers: stopped, .danglingImages: dangling, .unusedImages: tagged,
      .buildCache: cache, .networks: unusedNetworks, .anonymousVolumes: anonymous,
    ]
    return CleanupKind.allCases.map { kind in
      CleanupCategory(
        kind: kind,
        items: (groups[kind] ?? []).sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) })
    }
  }
}
