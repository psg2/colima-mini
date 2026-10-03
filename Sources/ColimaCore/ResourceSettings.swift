import Foundation

package struct ResourceSettings: Equatable {
    package let cpus: Int
    package let memoryGiB: Double
    // Colima can grow its data disk on the next start but never shrink it, so
    // saving rejects a smaller value. Nil leaves the configured size alone.
    package let diskGiB: Int?
    package init(cpus: Int, memoryGiB: Double, diskGiB: Int? = nil) {
        self.cpus = cpus
        self.memoryGiB = memoryGiB
        self.diskGiB = diskGiB
    }
    package static var configurationURL: URL {
        let home =
            ProcessInfo.processInfo.environment["COLIMA_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".colima")
        return home.appendingPathComponent("default/colima.yaml")
    }
    package static var hostCPUs: Int { ProcessInfo.processInfo.processorCount }
    package static var hostMemory: Int { Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) }
    // The disk image is sparse, so its size can exceed free space; cap it at the
    // Mac's own volume size.
    package static var hostDisk: Int {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bytes = (try? home.resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity
        return (bytes ?? 0) / 1_073_741_824
    }
    package func validate(maxCPUs: Int = Self.hostCPUs, maxMemory: Int = Self.hostMemory) throws {
        guard maxCPUs > 0, maxMemory > 0, (1...maxCPUs).contains(cpus),
            memoryGiB.isFinite, (1...Double(maxMemory)).contains(memoryGiB), (diskGiB ?? 1) > 0
        else {
            throw AppError.message("Choose 1–\(maxCPUs) CPUs and 1–\(maxMemory) GiB of memory.")
        }
    }
    package static func read(from url: URL = configurationURL) throws -> ResourceSettings {
        let text = try String(contentsOf: url, encoding: .utf8)
        func scalar(_ key: String, optional: Bool = false) throws -> Double? {
            let regex = try NSRegularExpression(
                pattern: "(?m)^" + key + #":[ \t]*([0-9]+(?:\.[0-9]+)?)[ \t]*(?:#.*)?$"#)
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            if optional && matches.isEmpty { return nil }
            guard matches.count == 1, let number = Range(matches[0].range(at: 1), in: text),
                let value = Double(text[number]), value.isFinite, value > 0
            else {
                throw AppError.message("Cannot read \(key) from the Colima configuration.")
            }
            return value
        }
        func whole(_ value: Double, _ what: String) throws -> Int {
            guard value.rounded() == value, value < Double(Int.max) else {
                throw AppError.message("\(what) must be a whole number.")
            }
            return Int(value)
        }
        let cpus = try whole(scalar("cpu")!, "CPU allocation")
        let disk = try scalar("disk", optional: true).map { try whole($0, "Disk size") }
        return try ResourceSettings(cpus: cpus, memoryGiB: scalar("memory")!, diskGiB: disk)
    }
    package func save(to url: URL = Self.configurationURL) throws {
        try validate()
        var text = try String(contentsOf: url, encoding: .utf8)
        let current = try Self.read(from: url)
        var values = [("cpu", String(cpus)), ("memory", String(memoryGiB))]
        if let diskGiB, diskGiB != current.diskGiB {
            guard let configured = current.diskGiB else {
                throw AppError.message("Cannot read disk from the Colima configuration.")
            }
            guard diskGiB > configured else {
                throw AppError.message("Colima can't shrink its disk below \(configured) GiB.")
            }
            values.append(("disk", String(diskGiB)))
        }
        for (key, value) in values {
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
