import Foundation

package struct Backend {
  package let fixture: Fixture?
  package let toolchain: Toolchain
  package let configurationURL: URL
  package init(
    fixture: Fixture? = nil, toolchain: Toolchain = Toolchain(),
    configurationURL: URL = ResourceSettings.configurationURL
  ) {
    self.fixture = fixture
    self.toolchain = toolchain
    self.configurationURL = configurationURL
  }
  package func settings() throws -> ResourceSettings {
    if let fixture {
      let vm = try fixture.snapshot.vm
      return ResourceSettings(cpus: vm.cpus, memoryGiB: Double(vm.memory) / 1_073_741_824)
    }
    return try ResourceSettings.read(from: configurationURL)
  }
  package func vm(_ verb: String) async throws -> String {
    guard fixture == nil else {
      throw AppError.message("Runtime actions are disabled in sample mode.")
    }
    guard ["start", "stop", "restart"].contains(verb) else {
      throw AppError.message("Unsupported VM action.")
    }
    return try await command("colima", [verb, "default"], timeout: 180)
  }
  private func command(
    _ name: String, _ arguments: [String], timeout: Double = 15,
    outputPolicy: Command.OutputPolicy = .stdout
  ) async throws
    -> String
  {
    try await Command.run(
      toolchain.executable(name), arguments, timeout: timeout, environment: toolchain.environment,
      outputPolicy: outputPolicy)
  }
  package func apply(_ resources: ResourceSettings, restart: Bool) async throws {
    guard fixture == nil else {
      throw AppError.message("Resource changes are disabled in sample mode.")
    }
    if !restart {
      try resources.save(to: configurationURL)
      return
    }
    let before = try await inventory()
    let previouslyRunning = Set(before.containers.filter(\.running).map(\.id))
    try resources.save(to: configurationURL)
    if before.vm.running { _ = try await vm("stop") }
    _ = try await command(
      "colima", ["start", "default", "--activate=false", "--save-config=false"], timeout: 240)
    let after = try await inventory()
    guard after.vm.running, after.vm.cpus == resources.cpus,
      abs(Double(after.vm.memory) / 1_073_741_824 - resources.memoryGiB) < 0.01
    else {
      throw AppError.message(
        "Resources were saved, but Colima did not start with the requested allocation. Check its status before retrying."
      )
    }
    let stopped = after.containers.filter { previouslyRunning.contains($0.id) && !$0.running }
    do {
      if !stopped.isEmpty { _ = try await docker(["start"] + stopped.map(\.id), timeout: 90) }
      let restored = try await inventory()
      let running = Set(restored.containers.filter(\.running).map(\.id))
      let missing = previouslyRunning.subtracting(running)
      guard missing.isEmpty else {
        throw AppError.message(
          "\(missing.count) previously running container(s) are missing or stopped.")
      }
    } catch {
      throw AppError.message(
        "Resources applied, but container restoration is incomplete: " + error.localizedDescription)
    }
  }
  package func docker(
    _ arguments: [String], timeout: Double = 15,
    outputPolicy: Command.OutputPolicy = .stdout
  ) async throws -> String {
    guard fixture == nil else {
      throw AppError.message("Runtime actions are disabled in sample mode.")
    }
    return try await command(
      "docker", ["--context", "colima"] + arguments, timeout: timeout, outputPolicy: outputPolicy)
  }
  private func inventory() async throws -> Snapshot {
    let vmOutput = try await command("colima", ["list", "--json"])
    let vmOnly = try Snapshot.decode(vm: vmOutput, containers: "", stats: "")
    guard vmOnly.vm.running else { return vmOnly }
    let containers = try await docker(["ps", "--all", "--no-trunc", "--format", "{{json .}}"])
    return try Snapshot.decode(vm: vmOutput, containers: containers, stats: "")
  }
  package func snapshot() async throws -> Snapshot {
    if let fixture { return try fixture.snapshot }
    let vmOutput = try await command("colima", ["list", "--json"])
    let vmOnly = try Snapshot.decode(vm: vmOutput, containers: "", stats: "")
    guard vmOnly.vm.running else { return vmOnly }
    async let containers = docker(["ps", "--all", "--no-trunc", "--format", "{{json .}}"])
    async let stats = docker(["stats", "--no-stream", "--format", "{{json .}}"])
    return try await Snapshot.decode(vm: vmOutput, containers: containers, stats: stats)
  }
  // The last 500 lines, then new output until the container stops or the
  // consumer stops iterating.
  package func followLogs(_ id: String) -> AsyncThrowingStream<String, Error> {
    if let fixture {
      let text = fixture.logs?[id] ?? "No logs in this sample."
      return AsyncThrowingStream { continuation in
        continuation.yield(text)
        continuation.finish()
      }
    }
    guard !id.isEmpty, !id.hasPrefix("-") else {
      return AsyncThrowingStream {
        $0.finish(throwing: AppError.message("The container identifier is invalid."))
      }
    }
    do {
      return Command.stream(
        try toolchain.executable("docker"),
        ["--context", "colima", "logs", "--follow", "--timestamps", "--tail", "500", id],
        environment: toolchain.environment)
    } catch {
      return AsyncThrowingStream { $0.finish(throwing: error) }
    }
  }
  package func sweep() async throws -> String {
    if let fixture { return fixture.sweep ?? "Nothing to clean up." }
    let bundle: Bundle
    if Bundle.main.bundleURL.pathExtension == "app" {
      guard
        let url = Bundle.main.url(forResource: "ColimaMini_ColimaCore", withExtension: "bundle"),
        let packaged = Bundle(url: url)
      else {
        throw AppError.message(
          "The cleanup scanner is missing from this app. Reinstall Colima Mini.")
      }
      bundle = packaged
    } else {
      bundle = Bundle.module
    }
    guard let script = bundle.url(forResource: "docker-sweep", withExtension: "py") else {
      throw AppError.message("The cleanup scanner is missing from this app. Reinstall Colima Mini.")
    }
    var environment = toolchain.environment
    environment["DOCKER_CONTEXT"] = "colima"
    environment["DOCKER_SWEEP_DOCKER"] = try toolchain.executable("docker")
    return try await Command.run(
      toolchain.executable("python3"), [script.path, "--sample", "2"], timeout: 45,
      environment: environment)
  }
}
