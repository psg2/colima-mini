import Darwin
import Foundation

package enum DiskBytes {
  package static func parse(_ text: String) -> Double? {
    let value =
      text.trimmingCharacters(in: .whitespaces)
      .components(separatedBy: " (").first ?? ""
    let units: [(String, Double)] = [
      ("TiB", pow(1024, 4)), ("GiB", pow(1024, 3)), ("MiB", pow(1024, 2)),
      ("KiB", 1024), ("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("B", 1),
    ]
    for (suffix, multiplier) in units where value.hasSuffix(suffix) {
      guard let number = Double(value.dropLast(suffix.count)), number.isFinite, number >= 0 else {
        return nil
      }
      let bytes = number * multiplier
      return bytes.isFinite ? bytes : nil
    }
    return nil
  }
}

package struct FilesystemUsage: Codable {
  package let sizeBytes: Int64
  package let usedBytes: Int64
  package let availableBytes: Int64
  package let mountpoint: String
  package var reservedBytes: Int64 { max(0, sizeBytes - usedBytes - availableBytes) }
  // Pulls and builds start failing well before the disk is full, so warn when
  // less than a tenth or less than 3 GiB is left, whichever comes first.
  package var isLow: Bool { availableBytes < max(sizeBytes / 10, 3 << 30) }

  package static func decode(_ output: String) throws -> FilesystemUsage {
    let rows = output.split(whereSeparator: \.isNewline).dropFirst()
    guard rows.count == 1,
      let row = rows.first,
      case let parts = row.split(whereSeparator: \.isWhitespace), parts.count >= 6,
      let size = Int64(parts[1]), let used = Int64(parts[2]), let available = Int64(parts[3]),
      size > 0, used >= 0, available >= 0, used <= size, available <= size - used
    else { throw AppError.message("The Docker data filesystem measurement is unavailable.") }
    return FilesystemUsage(
      sizeBytes: size, usedBytes: used, availableBytes: available,
      mountpoint: parts.dropFirst(5).joined(separator: " "))
  }
}

package struct DockerStorageCategory: Codable, Identifiable {
  package let type: String
  package let totalCount: Int?
  package let activeCount: Int?
  package let sizeBytes: Double?
  package let reclaimableBytes: Double?
  package var id: String { type }

  package static func decode(_ output: String) throws -> [DockerStorageCategory] {
    let rows = try Snapshot.lines(output, as: CategoryRow.self)
    guard !rows.isEmpty, Set(rows.map(\.type)).count == rows.count else {
      throw AppError.message("Docker returned an unsupported disk accounting response.")
    }
    return try rows.map {
      guard let size = DiskBytes.parse($0.size), let reclaimable = DiskBytes.parse($0.reclaimable),
        let total = Int($0.totalCount), let active = Int($0.active), total >= 0, active >= 0
      else { throw AppError.message("Docker returned an unsupported disk accounting measurement.") }
      return DockerStorageCategory(
        type: $0.type, totalCount: total, activeCount: active,
        sizeBytes: size, reclaimableBytes: reclaimable)
    }
  }
}

private struct CategoryRow: Decodable {
  let type: String
  let totalCount: String
  let active: String
  let size: String
  let reclaimable: String
  enum CodingKeys: String, CodingKey {
    case type = "Type"
    case totalCount = "TotalCount"
    case active = "Active"
    case size = "Size"
    case reclaimable = "Reclaimable"
  }
}

package struct StorageSnapshot: Codable {
  package let measuredAt: Date
  package let configuredCapacityBytes: Int64?
  package let filesystem: FilesystemUsage?
  package let docker: [DockerStorageCategory]
  package let hostAllocatedBytes: Int64?
  package let errors: [String: String]
}

package enum HostDiskFootprint {
  // This supported VZ layout has a named data image and a separate OS image.
  // Unknown Lima layouts remain unavailable rather than guessing from a large file.
  package static func allocatedBytes(home: URL) throws -> Int64 {
    let lima = home.appendingPathComponent("_lima")
    let config = lima.appendingPathComponent("colima/lima.yaml")
    let text = try String(contentsOf: config, encoding: .utf8)
    guard text.range(of: #"(?m)^vmType:\s*vz\s*$"#, options: .regularExpression) != nil,
      text.range(
        of: #"(?m)^additionalDisks:\s*\n(?:[ \t]+.*\n)*?[ \t]+- name: colima\s*$"#,
        options: .regularExpression) != nil
    else { throw AppError.message("Host disk footprint is unavailable for this Lima layout.") }
    let images = ["colima/disk", "_disks/colima/datadisk"]
    var identities = Set<String>()
    var allocated: Int64 = 0
    for image in images {
      let path = lima.appendingPathComponent(image).path
      var attributes = stat()
      guard lstat(path, &attributes) == 0,
        attributes.st_mode & S_IFMT == S_IFREG, attributes.st_size > 0,
        identities.insert("\(attributes.st_dev):\(attributes.st_ino)").inserted,
        attributes.st_blocks >= 0
      else { throw AppError.message("The Colima disk images could not be identified reliably.") }
      let (bytes, overflow) = Int64(attributes.st_blocks).multipliedReportingOverflow(by: 512)
      let (total, sumOverflow) = allocated.addingReportingOverflow(bytes)
      guard !overflow, !sumOverflow else {
        throw AppError.message("The Colima disk allocation measurement is too large.")
      }
      allocated = total
    }
    return allocated
  }
}
