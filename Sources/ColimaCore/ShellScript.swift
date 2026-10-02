import Foundation

// Interactive sessions run in the user's terminal, not inside the app. The
// script removes itself on launch and pins the colima context like other reads.
package enum ShellScript {
  package static func container(docker: String, id: String) throws -> String {
    guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
      throw AppError.message("The container identifier is invalid.")
    }
    return """
      #!/bin/sh
      rm -f "$0"
      unset DOCKER_HOST DOCKER_CONTEXT
      exec \(quote(docker)) --context colima exec -it \(id) sh -c \
      'if command -v bash >/dev/null 2>&1; then exec bash; else exec sh; fi'

      """
  }
  package static func folder(_ path: String) -> String {
    """
    #!/bin/sh
    rm -f "$0"
    cd \(quote(path)) || exit 1
    exec "${SHELL:-/bin/zsh}" -l

    """
  }
  // Writes a private, executable .command file that Terminal (or the user's
  // chosen handler) opens.
  package static func write(_ script: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "colima-mini-shell-" + UUID().uuidString + ".command")
    guard
      FileManager.default.createFile(
        atPath: url.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o700])
    else { throw AppError.message("The terminal launcher could not be created.") }
    return url
  }
  private static func quote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
  }
}
