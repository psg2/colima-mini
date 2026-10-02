import Foundation

// Files avoid pipe backpressure. Each command has private output files, a deadline,
// and cancellation that terminates the child rather than leaving it running.
package final class Command: @unchecked Sendable {
  package enum OutputPolicy { case stdout, combined }
  private let lock = NSLock()
  private let wake = DispatchSemaphore(value: 0)
  private var process: Process?
  private var cancelled = false
  package func cancel() {
    lock.lock()
    cancelled = true
    let child = process
    lock.unlock()
    wake.signal()
    if let child, child.isRunning { child.terminate() }
  }
  package func execute(
    _ executable: String, _ arguments: [String], timeout: Double,
    environment: [String: String], outputPolicy: OutputPolicy = .stdout
  ) throws -> String {
    guard FileManager.default.isExecutableFile(atPath: executable) else {
      throw AppError.message(
        "Missing \(URL(fileURLWithPath: executable).lastPathComponent). Install the required command-line tools first."
      )
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "colima-mini-" + UUID().uuidString)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let stdoutURL = directory.appendingPathComponent("stdout")
    let stderrURL = directory.appendingPathComponent("stderr")
    for url in [stdoutURL, stderrURL] {
      FileManager.default.createFile(
        atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
    let output = try FileHandle(forWritingTo: stdoutURL)
    let errors = try FileHandle(forWritingTo: stderrURL)
    defer {
      try? output.close()
      try? errors.close()
    }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: executable)
    child.arguments = arguments
    var env = ProcessInfo.processInfo.environment
    env.removeValue(forKey: "DOCKER_HOST")
    env.removeValue(forKey: "DOCKER_CONTEXT")
    env.merge(environment, uniquingKeysWith: { _, new in new })
    // Apps opened from Finder inherit launchd's minimal PATH. Colima runs limactl
    // by name, so the child needs the Homebrew directories too.
    env["PATH"] = Toolchain.searchPath(environment: env)
    child.environment = env
    child.standardInput = FileHandle.nullDevice
    child.standardOutput = output
    child.standardError = outputPolicy == .combined ? output : errors
    let finished = DispatchSemaphore(value: 0)
    child.terminationHandler = { [wake] _ in
      finished.signal()
      wake.signal()
    }
    lock.lock()
    if cancelled {
      lock.unlock()
      throw CancellationError()
    }
    process = child
    do {
      try child.run()
      lock.unlock()
    } catch {
      lock.unlock()
      throw error
    }
    let timedOut = wake.wait(timeout: .now() + timeout) == .timedOut
    lock.lock()
    let wasCancelled = cancelled
    lock.unlock()
    if timedOut || wasCancelled {
      if child.isRunning { child.terminate() }
      if finished.wait(timeout: .now() + 2) == .timedOut && child.isRunning {
        kill(child.processIdentifier, SIGKILL)
        child.waitUntilExit()
      }
    }
    lock.lock()
    let cancellationReceived = cancelled
    process = nil
    lock.unlock()
    if cancellationReceived { throw CancellationError() }
    if timedOut {
      throw AppError.message(
        "\(URL(fileURLWithPath: executable).lastPathComponent) timed out after \(Int(timeout)) seconds. Try Refresh."
      )
    }
    func read(_ url: URL) throws -> String {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let data = try handle.read(upToCount: 2_000_000) ?? Data()
      if data.count == 2_000_000 {
        throw AppError.message("Command output is too large to display.")
      }
      return String(decoding: data, as: UTF8.self)
    }
    let text = try read(stdoutURL)
    let errorText = try read(stderrURL)
    guard child.terminationStatus == 0 else {
      throw AppError.message(
        (outputPolicy == .combined ? text : errorText)
          .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? "Command failed with exit code \(child.terminationStatus)."
          : (outputPolicy == .combined ? text : errorText))
    }
    return text
  }
  package static func run(
    _ executable: String, _ arguments: [String], timeout: Double = 15,
    environment: [String: String] = [:], outputPolicy: OutputPolicy = .stdout
  ) async throws -> String {
    let command = Command()
    return try await withTaskCancellationHandler {
      try await Task.detached(priority: .utility) {
        try command.execute(
          executable, arguments, timeout: timeout, environment: environment,
          outputPolicy: outputPolicy)
      }.value
    } onCancel: {
      command.cancel()
    }
  }
}
