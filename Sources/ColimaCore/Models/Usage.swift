import Foundation

package struct Usage: Decodable {
  package let id: String
  package let cpuPercent: String
  package let memoryUsage: String
  package let memoryPercent: String
  // "received / sent", "read / written" and the process count, when Docker reports them.
  package var networkIO: String? = nil
  package var blockIO: String? = nil
  package var pids: String? = nil
  enum CodingKeys: String, CodingKey {
    case id = "ID"
    case cpuPercent = "CPUPerc"
    case memoryUsage = "MemUsage"
    case memoryPercent = "MemPerc"
    case networkIO = "NetIO"
    case blockIO = "BlockIO"
    case pids = "PIDs"
  }
  package var cpu: Double { Double(cpuPercent.replacingOccurrences(of: "%", with: "")) ?? 0 }
  package var memoryBytes: Double {
    let value = memoryUsage.components(separatedBy: " / ").first ?? ""
    let units: [(String, Double)] = [
      ("GiB", pow(1024, 3)), ("MiB", pow(1024, 2)),
      ("KiB", 1024), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("B", 1),
    ]
    for (suffix, multiplier) in units where value.hasSuffix(suffix) {
      return (Double(value.dropLast(suffix.count)) ?? 0) * multiplier
    }
    return 0
  }
}
