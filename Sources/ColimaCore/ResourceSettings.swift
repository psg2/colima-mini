import Foundation

package struct ResourceSettings: Equatable {
  package let cpus: Int
  package let memoryGiB: Double
  package init(cpus: Int, memoryGiB: Double) {
    self.cpus = cpus
    self.memoryGiB = memoryGiB
  }
  package static var configurationURL: URL {
    let home =
      ProcessInfo.processInfo.environment["COLIMA_HOME"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".colima")
    return home.appendingPathComponent("default/colima.yaml")
  }
  package static var hostCPUs: Int { ProcessInfo.processInfo.processorCount }
  package static var hostMemory: Int { Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) }
  package func validate(maxCPUs: Int = Self.hostCPUs, maxMemory: Int = Self.hostMemory) throws {
    guard maxCPUs > 0, maxMemory > 0, (1...maxCPUs).contains(cpus),
      memoryGiB.isFinite, (1...Double(maxMemory)).contains(memoryGiB)
    else {
      throw AppError.message("Choose 1–\(maxCPUs) CPUs and 1–\(maxMemory) GiB of memory.")
    }
  }
  package static func read(from url: URL = configurationURL) throws -> ResourceSettings {
    let text = try String(contentsOf: url, encoding: .utf8)
    func scalar(_ key: String) throws -> Double {
      let regex = try NSRegularExpression(
        pattern: "(?m)^" + key + #":[ \t]*([0-9]+(?:\.[0-9]+)?)[ \t]*(?:#.*)?$"#)
      let range = NSRange(text.startIndex..., in: text)
      let matches = regex.matches(in: text, range: range)
      guard matches.count == 1, let number = Range(matches[0].range(at: 1), in: text),
        let value = Double(text[number]), value.isFinite, value > 0
      else {
        throw AppError.message("Cannot read \(key) from the Colima configuration.")
      }
      return value
    }
    let cpus = try scalar("cpu")
    guard cpus.rounded() == cpus, cpus < Double(Int.max) else {
      throw AppError.message("CPU allocation must be a whole number.")
    }
    return try ResourceSettings(cpus: Int(cpus), memoryGiB: scalar("memory"))
  }
  package func save(to url: URL = Self.configurationURL) throws {
    try validate()
    var text = try String(contentsOf: url, encoding: .utf8)
    _ = try Self.read(from: url)
    for (key, value) in [("cpu", String(cpus)), ("memory", String(memoryGiB))] {
      let regex = try NSRegularExpression(
        pattern: "(?m)^" + key + #":[ \t]*([0-9]+(?:\.[0-9]+)?)[ \t]*(?:#.*)?$"#)
      guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let range = Range(match.range(at: 1), in: text)
      else {
        throw AppError.message("Cannot update \(key) in the Colima configuration.")
      }
      text.replaceSubrange(range, with: value)
    }
    let backup = url.deletingLastPathComponent().appendingPathComponent("colima.yaml.mini-backup")
    if !FileManager.default.fileExists(atPath: backup.path) {
      try FileManager.default.copyItem(at: url, to: backup)
    }
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
    try Data(text.utf8).write(to: url, options: .atomic)
    if let permissions {
      try FileManager.default.setAttributes(
        [.posixPermissions: permissions], ofItemAtPath: url.path)
    }
  }
}
