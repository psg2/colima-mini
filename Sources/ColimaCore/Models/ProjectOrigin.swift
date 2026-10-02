import Foundation

// Compose records the directory it ran in. Agent tools create worktrees under
// well-known roots, so the path explains otherwise opaque generated project names.
package struct ProjectOrigin: Equatable {
  package enum Kind: String {
    case claude = "Claude worktree"
    case codex = "Codex worktree"
    case conductor = "Conductor workspace"
    case orca = "Orca workspace"
    case folder = "Folder"
  }
  package let kind: Kind
  package let path: String
  package let repository: String
  package let worktree: String?
  private let home: String

  package init(path: String, home: String = NSHomeDirectory()) {
    let standardized = (path as NSString).standardizingPath
    let base = (home as NSString).standardizingPath
    self.path = standardized
    self.home = base
    let parts = standardized.split(separator: "/").map(String.init)
    func after(_ root: [String]) -> [String]? {
      let prefix = base.split(separator: "/").map(String.init) + root
      guard parts.count > prefix.count, Array(parts.prefix(prefix.count)) == prefix else {
        return nil
      }
      return Array(parts.dropFirst(prefix.count))
    }
    if let rest = after([".claude-worktrees"]), rest.count >= 2 {
      kind = .claude
      repository = rest[0]
      worktree = rest.dropFirst().joined(separator: "/")
    } else if let marker = parts.firstIndex(of: ".claude"), parts.count > marker + 2,
      parts[marker + 1] == "worktrees", marker > 0
    {
      kind = .claude
      repository = parts[marker - 1]
      worktree = parts.dropFirst(marker + 2).joined(separator: "/")
    } else if let rest = after([".codex", "worktrees"]), rest.count >= 2 {
      kind = .codex
      repository = rest[rest.count - 1]
      worktree = rest.dropLast().joined(separator: "/")
    } else if let rest = after(["conductor", "workspaces"]), rest.count >= 2 {
      kind = .conductor
      repository = rest[0]
      worktree = rest.dropFirst().joined(separator: "/")
    } else if let rest = after(["orca", "workspaces"]), rest.count >= 2 {
      kind = .orca
      repository = rest[0]
      worktree = rest.dropFirst().joined(separator: "/")
    } else {
      kind = .folder
      repository = parts.last ?? standardized
      worktree = nil
    }
  }

  package var url: URL { URL(fileURLWithPath: path) }
  package var displayPath: String {
    path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
  }
  package var summary: String {
    kind == .folder ? repository : "\(kind.rawValue) · \(repository)"
  }
  package func exists(fileManager: FileManager = .default) -> Bool {
    var directory: ObjCBool = false
    return fileManager.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
  }
}
