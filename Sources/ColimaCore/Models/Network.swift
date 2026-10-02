import Foundation

// One `docker network inspect` entry. Docker lists only running containers as
// members, so an empty network may still be referenced by stopped ones.
package struct DockerNetwork: Decodable, Identifiable, Equatable {
  package struct Member: Equatable, Identifiable {
    package let id: String
    package let name: String
    package let address: String?
  }
  package let id: String
  package let name: String
  package let driver: String
  package let scope: String
  package let `internal`: Bool
  package let created: String?
  package let subnets: [String]
  package let gateways: [String]
  package let members: [Member]
  package let project: String?

  // Docker creates these and refuses to remove them.
  package var builtin: Bool { ["bridge", "host", "none"].contains(name) }
  package var createdDate: Date? {
    created.flatMap {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter.date(from: $0)
        ?? ISO8601DateFormatter().date(
          from: $0.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression))
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id = "Id"
    case name = "Name"
    case driver = "Driver"
    case scope = "Scope"
    case `internal` = "Internal"
    case created = "Created"
    case ipam = "IPAM"
    case containers = "Containers"
    case labels = "Labels"
  }
  private struct IPAM: Decodable {
    struct Pool: Decodable {
      let subnet: String?
      let gateway: String?
      enum CodingKeys: String, CodingKey {
        case subnet = "Subnet"
        case gateway = "Gateway"
      }
    }
    let config: [Pool]?
    enum CodingKeys: String, CodingKey { case config = "Config" }
  }
  private struct Endpoint: Decodable {
    let name: String
    let address: String?
    enum CodingKeys: String, CodingKey {
      case name = "Name"
      case address = "IPv4Address"
    }
  }
  package init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    driver = try values.decodeIfPresent(String.self, forKey: .driver) ?? ""
    scope = try values.decodeIfPresent(String.self, forKey: .scope) ?? ""
    `internal` = try values.decodeIfPresent(Bool.self, forKey: .internal) ?? false
    created = try values.decodeIfPresent(String.self, forKey: .created)
    let pools = try values.decodeIfPresent(IPAM.self, forKey: .ipam)?.config ?? []
    subnets = pools.compactMap(\.subnet)
    gateways = pools.compactMap(\.gateway)
    let endpoints = try values.decodeIfPresent([String: Endpoint].self, forKey: .containers) ?? [:]
    members = endpoints.map {
      Member(
        id: $0.key, name: $0.value.name,
        address: $0.value.address.flatMap { $0.isEmpty ? nil : $0 })
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    let labels = try values.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
    project = labels["com.docker.compose.project"].flatMap { $0.isEmpty ? nil : $0 }
  }
}

extension Backend {
  package func networks() async throws -> [DockerNetwork] {
    if let fixture { return fixture.networks ?? [] }
    let ids = try await docker(["network", "ls", "--quiet", "--no-trunc"])
      .split(whereSeparator: \.isNewline).map(String.init)
    guard !ids.isEmpty else { return [] }
    let output = try await docker(["network", "inspect"] + ids)
    return try JSONDecoder().decode([DockerNetwork].self, from: Data(output.utf8))
      .sorted { lhs, rhs in
        lhs.builtin != rhs.builtin
          ? !lhs.builtin : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
  }
  // Without --force: Docker refuses a network that a container still uses.
  package func removeNetwork(_ network: DockerNetwork) async throws {
    guard !network.builtin else {
      throw AppError.message("Docker's built-in \(network.name) network can't be removed.")
    }
    _ = try await docker(["network", "rm", network.id])
  }
}
