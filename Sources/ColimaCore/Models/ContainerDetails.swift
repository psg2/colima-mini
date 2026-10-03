import Foundation

package struct ContainerState: Codable {
    package let status: String?
    package let running: Bool?
    package let exitCode: Int?
    package let oomKilled: Bool?
    package let startedAt: String?
    package let finishedAt: String?
    package let error: String?
    package let health: String?
}

package struct PortBinding: Codable, Identifiable {
    package let hostAddress: String
    package let hostPort: String
    package let containerPort: String
    package let protocolName: String
    package var id: String { "\(hostAddress):\(hostPort)->\(containerPort)/\(protocolName)" }
    package var address: String {
        let host = hostAddress.contains(":") ? "[\(hostAddress)]" : hostAddress
        return "\(host):\(hostPort)"
    }
}

package struct ContainerMount: Codable, Identifiable {
    package let type: String
    package let name: String?
    package let source: String
    package let destination: String
    package let readOnly: Bool
    package var id: String { "\(type):\(source):\(destination)" }
}

package struct ContainerDetails: Codable, Identifiable {
    package let id: String
    package let name: String
    package let image: String
    package let imageID: String
    package let state: ContainerState
    package let restartCount: Int?
    package let ports: [PortBinding]
    package let mounts: [ContainerMount]
    package let project: String?
    package let service: String?
    package var mountsAvailable: Bool? = nil

    // Decode only inspection fields used by the app, never Config.Env or health probe output.
    package static func decode(_ output: String) throws -> [ContainerDetails] {
        try Snapshot.lines(output, as: DockerInspection.self).map(\.details)
    }
}

private struct DockerInspection: Decodable {
    let id: String
    let name: String
    let image: String
    let config: Configuration
    let state: StateInfo
    let restartCount: Int?
    let mounts: [Mount]?
    let networkSettings: Network?
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case image = "Image"
        case config = "Config"
        case state = "State"
        case restartCount = "RestartCount"
        case mounts = "Mounts"
        case networkSettings = "NetworkSettings"
    }
    struct Configuration: Decodable {
        let image: String
        let labels: [String: String?]?
        enum CodingKeys: String, CodingKey {
            case image = "Image"
            case labels = "Labels"
        }
    }
    struct StateInfo: Decodable {
        let status: String?
        let running: Bool?
        let exitCode: Int?
        let oomKilled: Bool?
        let startedAt: String?
        let finishedAt: String?
        let error: String?
        let health: HealthInfo?
        enum CodingKeys: String, CodingKey {
            case status = "Status"
            case running = "Running"
            case exitCode = "ExitCode"
            case oomKilled = "OOMKilled"
            case startedAt = "StartedAt"
            case finishedAt = "FinishedAt"
            case error = "Error"
            case health = "Health"
        }
    }
    struct HealthInfo: Decodable {
        let status: String?
        enum CodingKeys: String, CodingKey { case status = "Status" }
    }
    struct Mount: Decodable {
        let type: String
        let name: String?
        let source: String
        let destination: String
        let readWrite: Bool?
        enum CodingKeys: String, CodingKey {
            case type = "Type"
            case name = "Name"
            case source = "Source"
            case destination = "Destination"
            case readWrite = "RW"
        }
    }
    struct Network: Decodable {
        let ports: [String: [Binding]?]?
        enum CodingKeys: String, CodingKey { case ports = "Ports" }
    }
    struct Binding: Decodable {
        let hostIp: String
        let hostPort: String
        enum CodingKeys: String, CodingKey {
            case hostIp = "HostIp"
            case hostPort = "HostPort"
        }
    }
    var details: ContainerDetails {
        let ports = (networkSettings?.ports ?? [:]).flatMap { key, bindings -> [PortBinding] in
            let pieces = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { return [] }
            return (bindings ?? []).map {
                PortBinding(
                    hostAddress: $0.hostIp, hostPort: $0.hostPort,
                    containerPort: pieces[0], protocolName: pieces[1])
            }
        }.sorted { $0.id < $1.id }
        return ContainerDetails(
            id: id, name: name.hasPrefix("/") ? String(name.dropFirst()) : name,
            image: config.image, imageID: image,
            state: ContainerState(
                status: state.status, running: state.running, exitCode: state.exitCode,
                oomKilled: state.oomKilled, startedAt: state.startedAt, finishedAt: state.finishedAt,
                error: state.error, health: state.health?.status),
            restartCount: restartCount, ports: ports,
            mounts: (mounts ?? []).map {
                ContainerMount(
                    type: $0.type, name: $0.name, source: $0.source,
                    destination: $0.destination, readOnly: $0.readWrite == false)
            },
            project: (config.labels?["com.docker.compose.project"] ?? nil).flatMap {
                $0.isEmpty ? nil : $0
            },
            service: (config.labels?["com.docker.compose.service"] ?? nil).flatMap {
                $0.isEmpty ? nil : $0
            }, mountsAvailable: mounts != nil)
    }
}
