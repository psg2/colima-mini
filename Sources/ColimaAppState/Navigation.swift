import Foundation

package enum AppRoute: Hashable {
  case containers
  case container(String)
  case volumes
  case volume(String)
  case images
  case image(String)
  case storage
  case settings

  package var section: AppRoute {
    switch self {
    case .container: return .containers
    case .volume: return .volumes
    case .image: return .images
    default: return self
    }
  }
}

package struct MetricSample: Identifiable {
  package let id = UUID()
  package let date: Date
  package let cpu: Double
  package let memory: Double
}
