import Foundation

package enum AppRoute: Hashable {
  case overview
  case containers
  case container(String)
  case projectLogs(String)
  case volumes
  case volume(String)
  case images
  case image(String)
  case networks
  case storage
  case settings

  // Top-level pages the app reopens on the next launch.
  package var sectionName: String? {
    switch self {
    case .overview: return "overview"
    case .containers: return "containers"
    case .volumes: return "volumes"
    case .images: return "images"
    case .networks: return "networks"
    case .storage: return "storage"
    default: return nil
    }
  }
  package var section: AppRoute {
    switch self {
    case .container, .projectLogs: return .containers
    case .volume: return .volumes
    case .image: return .images
    default: return self
    }
  }
}

package enum ContainerPageTab: String, CaseIterable {
  case overview = "Overview"
  case logs = "Logs"
  case ports = "Ports"
  case mounts = "Mounts"
  case environment = "Env"
}

package enum VolumeKind: String, CaseIterable {
  case all = "All"
  case named = "Named"
  case anonymous = "Anonymous"
}

package struct MetricSample: Identifiable {
  package let id = UUID()
  package let date: Date
  package let cpu: Double
  package let memory: Double
}
