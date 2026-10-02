import Foundation

extension Backend {
  // The template excludes environment variables, arbitrary labels and health probe output.
  private static let inspectionFormat =
    #"{"Id":{{json .Id}},"Name":{{json .Name}},"Image":{{json .Image}},"Config":{"Image":{{json .Config.Image}},"Labels":{"com.docker.compose.project":{{json (index .Config.Labels "com.docker.compose.project")}},"com.docker.compose.service":{{json (index .Config.Labels "com.docker.compose.service")}}}},"State":{"Status":{{json .State.Status}},"Running":{{json .State.Running}},"ExitCode":{{json .State.ExitCode}},"OOMKilled":{{json .State.OOMKilled}},"StartedAt":{{json .State.StartedAt}},"FinishedAt":{{json .State.FinishedAt}},"Error":{{json .State.Error}},"Health":{{with (index .State "Health")}}{"Status":{{json (index . "Status")}}}{{else}}null{{end}}},"RestartCount":{{json .RestartCount}},"Mounts":{{json .Mounts}},"NetworkSettings":{"Ports":{{json .NetworkSettings.Ports}}}}"#

  package func details(_ id: String) async throws -> ContainerDetails {
    if let fixture {
      guard let details = fixture.details?[id] else {
        throw AppError.message("Inspection is unavailable for this sample container.")
      }
      return details
    }
    guard !id.isEmpty, !id.hasPrefix("-") else {
      throw AppError.message("The container identifier is invalid.")
    }
    let output = try await docker([
      "inspect", "--type", "container", "--format", Self.inspectionFormat, id,
    ])
    guard let details = try ContainerDetails.decode(output).first,
      details.id == id || details.id.hasPrefix(id)
    else {
      throw AppError.message("This container no longer exists. Return to Containers and refresh.")
    }
    return details
  }

  private func allInspections() async throws -> [ContainerDetails] {
    let output = try await docker(["ps", "--all", "--quiet", "--no-trunc"])
    let ids = output.split(whereSeparator: \.isNewline).map(String.init)
    var details: [ContainerDetails] = []
    // Bound argv/output for large inventories without one subprocess per row.
    for offset in stride(from: 0, to: ids.count, by: 100) {
      let batch = Array(ids[offset..<min(offset + 100, ids.count)])
      let inspected = try await docker(
        ["inspect", "--type", "container", "--format", Self.inspectionFormat] + batch)
      let rows = try ContainerDetails.decode(inspected)
      guard rows.count == batch.count, Set(rows.map(\.id)) == Set(batch) else {
        throw AppError.message("Container references could not be measured completely.")
      }
      details += rows
    }
    return details
  }

  private func accounting() async throws -> DockerAccounting {
    let output = try await docker(
      ["system", "df", "--verbose", "--format", "{{json .}}"], timeout: 45)
    return try JSONDecoder().decode(DockerAccounting.self, from: Data(output.utf8))
  }

  package func volumes() async throws -> [Volume] {
    if let fixture { return fixture.volumes ?? [] }
    let output = try await docker(["volume", "ls", "--format", "{{json .}}"])
    let rows = try Snapshot.lines(output, as: VolumeListRow.self)
    if rows.isEmpty { return [] }
    async let inspections = captured { try await self.allInspections() }
    async let accounting = captured { try await self.accounting() }
    async let metadata = captured {
      let format =
        #"{"Name":{{json .Name}},"Driver":{{json .Driver}},"Mountpoint":{{json .Mountpoint}},"CreatedAt":{{json .CreatedAt}},"Labels":{{json .Labels}}}"#
      var all: [VolumeMetadata] = []
      let names = rows.map(\.name)
      for offset in stride(from: 0, to: names.count, by: 100) {
        let batch = Array(names[offset..<min(offset + 100, names.count)])
        let output = try await self.docker(["volume", "inspect", "--format", format] + batch)
        all += try Snapshot.lines(output, as: VolumeMetadata.self)
      }
      return all
    }
    let (referenceResult, usage, attributes) = await (inspections, accounting, metadata)
    let details = (try? referenceResult.get()) ?? []
    let info = (try? attributes.get()) ?? []
    let measured = (try? usage.get())?.volumes ?? []
    let completeReferences =
      referenceResult.errorDescription == nil && details.allSatisfy { $0.mountsAvailable == true }
    let incompleteIssue =
      completeReferences ? nil : "Container references are unavailable or incomplete."
    let issue = [
      referenceResult.errorDescription, usage.errorDescription, attributes.errorDescription,
      incompleteIssue,
    ]
    .compactMap { $0 }.joined(separator: "\n")
    return rows.map { row in
      let meta = info.first { $0.name == row.name }
      let size = measured.first { $0.name == row.name }.flatMap { DiskBytes.parse($0.size) }
      let references = details.flatMap { container in
        container.mounts.filter { $0.type == "volume" && $0.name == row.name }.map {
          VolumeReference(
            containerID: container.id, containerName: container.name,
            destination: $0.destination, readOnly: $0.readOnly,
            running: container.state.running == true)
        }
      }.sorted { $0.id < $1.id }
      return Volume(
        name: row.name, driver: meta?.driver ?? row.driver,
        project: (meta?.labels?["com.docker.compose.project"] ?? nil).flatMap {
          $0.isEmpty ? nil : $0
        },
        mountpoint: meta?.mountpoint, createdAt: meta?.createdAt, sizeBytes: size,
        references: references, referencesAvailable: completeReferences,
        dataIssue: issue.isEmpty ? nil : issue,
        anonymous: meta.map { $0.labels?.keys.contains("com.docker.volume.anonymous") == true })
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  package func images() async throws -> [DockerImage] {
    if let fixture { return fixture.images ?? [] }
    async let inspectionResult = captured { try await self.allInspections() }
    let usage = try await accounting()
    let result = await inspectionResult
    let details = (try? result.get()) ?? []
    return usage.images.map { row in
      let references = DockerImage.referencingContainers(
        imageID: row.id, containers: details, knownImageIDs: usage.images.map(\.id))
      return DockerImage(
        imageID: row.id, repository: row.repository, tag: row.tag,
        sizeBytes: DiskBytes.parse(row.size), sharedBytes: DiskBytes.parse(row.sharedSize),
        uniqueBytes: DiskBytes.parse(row.uniqueSize),
        containerIDs: references ?? [],
        referencesAvailable: result.errorDescription == nil && references != nil)
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  package func storage() async throws -> StorageSnapshot {
    if let fixture {
      if let storage = fixture.storage { return storage }
      return StorageSnapshot(
        measuredAt: Date(), configuredCapacityBytes: try fixture.snapshot.vm.disk,
        filesystem: nil, docker: [], hostAllocatedBytes: nil,
        errors: [
          "filesystem": "No sample measurement.", "docker": "No sample measurement.",
          "host": "No sample measurement.",
        ])
    }
    var errors: [String: String] = [:]
    let vmResult = await captured {
      let output = try await self.colimaRead(["list", "--json"])
      guard let vm = try Snapshot.lines(output, as: VM.self).first(where: { $0.name == "default" })
      else { throw AppError.message("The default Colima profile is missing.") }
      return vm
    }
    let vm = try? vmResult.get()
    if let error = vmResult.errorDescription { errors["capacity"] = error }
    let capacity = vm?.disk.flatMap { $0 > 0 ? $0 : nil }
    if capacity == nil && errors["capacity"] == nil {
      errors["capacity"] = "Colima did not report the configured disk capacity."
    }
    async let host = captured {
      let home =
        self.toolchain.environment["COLIMA_HOME"].map {
          URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".colima")
      return try HostDiskFootprint.allocatedBytes(home: home)
    }
    var filesystem: FilesystemUsage?
    var docker: [DockerStorageCategory] = []
    if vm?.running == true {
      async let filesystemResult = captured {
        let root = try await self.docker(["info", "--format", "{{.DockerRootDir}}"])
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard root.range(of: #"^/[A-Za-z0-9_./-]+$"#, options: .regularExpression) != nil else {
          throw AppError.message("Docker did not report a usable data filesystem path.")
        }
        let output = try await self.colimaRead([
          "ssh", "--profile", "default", "--", "env", "LC_ALL=C", "df", "-P", "-B1", root,
        ])
        return try FilesystemUsage.decode(output)
      }
      async let dockerResult = captured {
        let output = try await self.docker(["system", "df", "--format", "{{json .}}"], timeout: 45)
        return try DockerStorageCategory.decode(output)
      }
      let (fs, categories) = await (filesystemResult, dockerResult)
      filesystem = try? fs.get()
      docker = (try? categories.get()) ?? []
      errors["filesystem"] = fs.errorDescription
      errors["docker"] = categories.errorDescription
    } else {
      errors["filesystem"] = "Start Colima to measure the Docker data filesystem."
      errors["docker"] = "Start Colima to measure Docker storage."
    }
    let hostResult = await host
    errors["host"] = hostResult.errorDescription
    return StorageSnapshot(
      measuredAt: Date(), configuredCapacityBytes: capacity, filesystem: filesystem,
      docker: docker, hostAllocatedBytes: try? hostResult.get(), errors: errors)
  }

  private func colimaRead(_ arguments: [String]) async throws -> String {
    try await Command.run(
      toolchain.executable("colima"), arguments, timeout: 20, environment: toolchain.environment)
  }
}

private func captured<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
  do { return .success(try await operation()) } catch { return .failure(error) }
}

extension Result where Failure == Error {
  fileprivate var errorDescription: String? {
    if case .failure(let error) = self { return error.localizedDescription }
    return nil
  }
}

private struct VolumeListRow: Decodable {
  let name: String
  let driver: String
  enum CodingKeys: String, CodingKey {
    case name = "Name"
    case driver = "Driver"
  }
}
private struct VolumeMetadata: Decodable {
  let name: String
  let driver: String
  let mountpoint: String?
  let createdAt: String?
  let labels: [String: String?]?
  enum CodingKeys: String, CodingKey {
    case name = "Name"
    case driver = "Driver"
    case mountpoint = "Mountpoint"
    case createdAt = "CreatedAt"
    case labels = "Labels"
  }
}
private struct DockerAccounting: Decodable {
  let images: [ImageRow]
  let volumes: [VolumeRow]
  enum CodingKeys: String, CodingKey {
    case images = "Images"
    case volumes = "Volumes"
  }
  struct VolumeRow: Decodable {
    let name: String
    let size: String
    enum CodingKeys: String, CodingKey {
      case name = "Name"
      case size = "Size"
    }
  }
  struct ImageRow: Decodable {
    let id: String
    let repository: String
    let tag: String
    let size: String
    let sharedSize: String
    let uniqueSize: String
    enum CodingKeys: String, CodingKey {
      case id = "ID"
      case repository = "Repository"
      case tag = "Tag"
      case size = "Size"
      case sharedSize = "SharedSize"
      case uniqueSize = "UniqueSize"
    }
  }
}
