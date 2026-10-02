import Foundation

// One `Config.Env` entry. Names that usually hold credentials, and URLs with a
// password, are sensitive: the app masks them until the user reveals one.
package struct EnvironmentVariable: Identifiable, Equatable {
  package let name: String
  package let value: String
  package var id: String { name }

  // Long words match inside a name part (DBPASSWORD); short ones only as a
  // whole part, so KEYBOARD or AUTHOR stay visible.
  private static let sensitiveFragments = [
    "PASSWORD", "PASSWD", "SECRET", "TOKEN", "CREDENTIAL", "PRIVATE", "APIKEY",
  ]
  private static let sensitiveParts: Set<String> = [
    "PASS", "PWD", "KEY", "KEYS", "AUTH", "SESSION", "COOKIE", "SALT", "SIGNATURE", "CERT", "DSN",
  ]
  // Shell and locale variables that end in a sensitive-looking word.
  private static let knownSafe: Set<String> = ["PWD", "OLDPWD"]

  package var sensitive: Bool {
    if Self.knownSafe.contains(name) { return false }
    let words = name.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    if words.contains(where: { word in
      Self.sensitiveParts.contains(String(word))
        || Self.sensitiveFragments.contains { word.contains($0) }
    }) {
      return true
    }
    // postgres://user:secret@host and similar.
    return value.range(
      of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://[^/@\s:]*:[^/@\s]+@"#, options: .regularExpression)
      != nil
  }

  package static func parse(_ entries: [String]) -> [EnvironmentVariable] {
    entries.map { entry in
      let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      return EnvironmentVariable(
        name: String(parts[0]), value: parts.count > 1 ? String(parts[1]) : "")
    }
  }
}

extension Backend {
  // Read only when the Env tab is open. Regular inspection never includes it.
  package func environment(_ id: String) async throws -> [EnvironmentVariable] {
    if let fixture { return EnvironmentVariable.parse(fixture.environment?[id] ?? []) }
    guard !id.isEmpty, !id.hasPrefix("-") else {
      throw AppError.message("The container identifier is invalid.")
    }
    let output = try await docker(
      ["inspect", "--type", "container", "--format", "{{json .Config.Env}}", id])
    let entries = try JSONDecoder().decode([String]?.self, from: Data(output.utf8)) ?? []
    return EnvironmentVariable.parse(entries)
  }
}
