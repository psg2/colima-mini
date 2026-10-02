import Foundation

// A transition worth interrupting the user for. Alerts compare two snapshots,
// so a container that was already failing when the app opened stays quiet.
package struct ContainerAlert: Equatable, Identifiable {
  package enum Kind: Equatable {
    case exited(Int?)
    case unhealthy
    case restarting
  }
  package let containerID: String
  package let name: String
  package let project: String
  package let kind: Kind
  package var id: String { "\(containerID):\(kind)" }

  package var title: String {
    switch kind {
    case .exited(137): return "\(name) was killed (exit 137)"
    case .exited(let code): return "\(name) exited" + (code.map { " with code \($0)" } ?? "")
    case .unhealthy: return "\(name) is unhealthy"
    case .restarting: return "\(name) is restarting"
    }
  }
  package var message: String {
    switch kind {
    case .exited(137): return "\(project) · Out of memory or a forced stop. Check its logs."
    case .exited: return "\(project) · The container stopped unexpectedly."
    case .unhealthy: return "\(project) · Its health check is failing."
    case .restarting: return "\(project) · Docker is restarting it after a failure."
    }
  }

  package static func changes(from old: [Container], to new: [Container]) -> [ContainerAlert] {
    let previous = Dictionary(old.map { ($0.id, $0.condition) }, uniquingKeysWith: { a, _ in a })
    return new.compactMap { container in
      guard let before = previous[container.id] else { return nil }
      let kind: Kind
      switch (before, container.condition) {
      // 143 is SIGTERM, the normal result of docker stop for many images.
      case (.exited, .exited), (_, .exited(0)), (_, .exited(143)): return nil
      case (_, .exited(let code)): kind = .exited(code)
      case (.unhealthy, .unhealthy), (.restarting, .restarting): return nil
      case (_, .unhealthy): kind = .unhealthy
      case (_, .restarting): kind = .restarting
      default: return nil
      }
      return ContainerAlert(
        containerID: container.id, name: container.name, project: container.project, kind: kind)
    }
  }
}
