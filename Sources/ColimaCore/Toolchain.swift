import Foundation

package struct Toolchain {
    package let environment: [String: String]
    package init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        var sanitized = environment
        sanitized.removeValue(forKey: "DOCKER_HOST")
        sanitized.removeValue(forKey: "DOCKER_CONTEXT")
        self.environment = sanitized
    }
    package static func searchPath(environment: [String: String]) -> String {
        var seen = Set<String>()
        return
            ((environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"])
            .filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }
    package func executable(_ name: String) throws -> String {
        if let override = environment["COLIMA_MINI_" + name.uppercased()] {
            guard override.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: override) else {
                throw AppError.message("The configured \(name) executable is missing or not executable.")
            }
            return override
        }
        for directory in Self.searchPath(environment: environment).split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw AppError.message("Missing \(name). Install it and reopen Colima Mini.")
    }
}
