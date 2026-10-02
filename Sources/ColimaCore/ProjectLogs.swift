import Foundation

package struct LogSource: Equatable {
  package let id: String
  package let label: String
  package init(id: String, label: String) {
    self.id = id
    self.label = label
  }
}

extension Backend {
  // Several containers' followed logs as one stream of complete lines. Each line
  // keeps Docker's leading timestamp, then names its source: "TIMESTAMP [web] text".
  // The stream ends when every source ends; the first failure ends it early.
  package func followProjectLogs(_ sources: [LogSource]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try await withThrowingTaskGroup(of: Void.self) { group in
            for source in sources {
              group.addTask {
                var splitter = LineSplitter()
                for try await chunk in self.followLogs(source.id) {
                  let lines = splitter.feed(chunk)
                  if !lines.isEmpty {
                    continuation.yield(lines.map { Self.label($0, source.label) }.joined())
                  }
                }
                if let rest = splitter.finish() {
                  continuation.yield(Self.label(rest, source.label))
                }
              }
            }
            try await group.waitForAll()
          }
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  static func label(_ line: String, _ source: String) -> String {
    let body = line.hasSuffix("\n") ? String(line.dropLast()) : line
    guard let space = body.firstIndex(of: " "), body.prefix(4).allSatisfy(\.isNumber) else {
      return "[\(source)] \(body)\n"
    }
    return "\(body[..<space]) [\(source)]\(body[space...])\n"
  }
}

// Joins pipe reads into whole lines so interleaved sources never split a line.
struct LineSplitter {
  private var pending = ""
  mutating func feed(_ chunk: String) -> [String] {
    pending += chunk
    guard let last = pending.lastIndex(of: "\n") else { return [] }
    let complete = pending[...last]
    pending = String(pending[pending.index(after: last)...])
    return complete.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
      .map { $0 + "\n" }
  }
  mutating func finish() -> String? {
    defer { pending = "" }
    return pending.isEmpty ? nil : pending
  }
}
