import Foundation

package struct Snapshot {
  package let vm: VM
  package let containers: [Container]
  package let usage: [String: Usage]
  package var projects: [String] { Array(Set(containers.map(\.project))).sorted() }
  package static func lines<T: Decodable>(_ text: String, as type: T.Type) throws -> [T] {
    try text.split(whereSeparator: \.isNewline).filter {
      !$0.trimmingCharacters(in: .whitespaces).isEmpty
    }
    .map { try JSONDecoder().decode(type, from: Data($0.utf8)) }
  }
  package static func decode(vm: String, containers: String, stats: String) throws -> Snapshot {
    guard let profile = try lines(vm, as: VM.self).first(where: { $0.name == "default" }) else {
      throw AppError.message(
        "The default Colima profile is missing. Create it with colima start first.")
    }
    if !profile.running { return Snapshot(vm: profile, containers: [], usage: [:]) }
    let rows = try lines(containers, as: Container.self).sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    let metrics = try lines(stats, as: Usage.self)
    return Snapshot(
      vm: profile, containers: rows,
      usage: Dictionary(metrics.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }))
  }
  package func metric(for container: Container) -> Usage? {
    guard container.running else { return nil }
    return usage[container.id] ?? usage.first(where: { container.id.hasPrefix($0.key) })?.value
  }
  package func totalCPU(_ containers: [Container]) -> Double {
    containers.compactMap { metric(for: $0)?.cpu }.reduce(0, +)
  }
  package func totalMemory(_ containers: [Container]) -> Double {
    containers.compactMap { metric(for: $0)?.memoryBytes }.reduce(0, +)
  }
  package var summary: [String: Any] {
    [
      "status": vm.status, "cpus": vm.cpus, "memoryGiB": vm.memory / 1_073_741_824,
      "containers": containers.count, "running": containers.filter(\.running).count,
      "projects": projects,
      "localhostPorts": containers.flatMap(\.endpoints).compactMap(\.port).sorted(),
      "totalCPU": totalCPU(containers), "totalMemoryBytes": totalMemory(containers),
      "metrics": containers.compactMap { c -> [String: String]? in
        guard let m = metric(for: c) else { return nil }
        return ["name": c.name, "cpu": m.cpuPercent, "memory": m.memoryUsage]
      },
    ]
  }
}
