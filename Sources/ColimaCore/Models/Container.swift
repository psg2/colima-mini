import Foundation

package struct Container: Decodable, Identifiable {
    package let dockerID: String
    package let name: String
    package let image: String
    package let state: String
    package let status: String
    package let ports: String
    package let labels: String
    enum CodingKeys: String, CodingKey {
        case dockerID = "ID"
        case name = "Names"
        case image = "Image"
        case state = "State"
        case status = "Status"
        case ports = "Ports"
        case labels = "Labels"
    }

    package var id: String { dockerID }
    package var running: Bool { state == "running" }
    package func label(_ key: String) -> String? {
        let prefix = key + "="
        return labels.components(separatedBy: ",").first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
    }
    package var project: String { label("com.docker.compose.project") ?? "Standalone" }
    package var service: String { label("com.docker.compose.service") ?? name }
    package var needsAttention: Bool { condition.failed }
    package var folder: URL? {
        label("com.docker.compose.project.working_dir").map { URL(fileURLWithPath: $0) }
    }
    package var origin: ProjectOrigin? {
        label("com.docker.compose.project.working_dir").flatMap {
            $0.hasPrefix("/") ? ProjectOrigin(path: $0) : nil
        }
    }
    package var condition: ContainerCondition {
        ContainerCondition(state: state, status: status)
    }
    // Docker's status without its health suffix, such as "Up 2 hours".
    package var uptime: String {
        status.replacingOccurrences(
            of: #"\s*\((?:healthy|unhealthy|health: starting)\)$"#, with: "", options: .regularExpression)
    }
    // Compiled once: rows read ports on every render.
    private static let publishedPortPattern = try! NSRegularExpression(
        pattern: #"(?:^|,\s*)(127\.0\.0\.1|0\.0\.0\.0|\[::\]|\[::1\]):(\d+)->(\d+)/(tcp|udp)"#)
    // Ports Docker publishes on the Mac's loopback or wildcard addresses. IPv4 and
    // IPv6 bindings of one host port collapse into a single entry.
    package var publishedPorts: [PublishedPort] {
        let text = ports as NSString
        var seen = Set<String>()
        return Self.publishedPortPattern.matches(in: ports, range: NSRange(location: 0, length: text.length)).compactMap {
            match in
            guard let host = Int(text.substring(with: match.range(at: 2))),
                let target = Int(text.substring(with: match.range(at: 3)))
            else { return nil }
            let port = PublishedPort(
                hostPort: host, containerPort: target,
                protocolName: text.substring(with: match.range(at: 4)))
            return seen.insert(port.id).inserted ? port : nil
        }
    }
    package var endpoints: [URL] {
        publishedPorts.compactMap { $0.url(scheme: $0.containerPort == 443 ? "https" : "http") }
    }
}

package struct PublishedPort: Hashable, Identifiable {
    package let hostPort: Int
    package let containerPort: Int
    package let protocolName: String
    package var id: String { "\(hostPort)/\(protocolName)" }
    package var label: String { "\(hostPort)→\(containerPort)" }
    package var address: String { "localhost:\(hostPort)" }
    package func url(scheme: String) -> URL? {
        protocolName == "tcp" ? URL(string: "\(scheme)://localhost:\(hostPort)") : nil
    }
}

package enum ContainerCondition: Equatable {
    case healthy, unhealthy, starting, running, restarting, paused, created, dead
    case exited(Int?)
    case other(String)

    package init(state: String, status: String) {
        switch state {
        case "running":
            if status.hasSuffix("(unhealthy)") {
                self = .unhealthy
            } else if status.hasSuffix("(healthy)") {
                self = .healthy
            } else if status.hasSuffix("(health: starting)") {
                self = .starting
            } else {
                self = .running
            }
        case "restarting": self = .restarting
        case "paused": self = .paused
        case "created": self = .created
        case "dead": self = .dead
        case "exited":
            let code = status.range(of: #"(?<=Exited \()-?\d+(?=\))"#, options: .regularExpression)
                .flatMap { Int(status[$0]) }
            self = .exited(code)
        default: self = .other(state)
        }
    }
    package var title: String {
        switch self {
        case .healthy: return "Healthy"
        case .unhealthy: return "Unhealthy"
        case .starting: return "Starting"
        case .running: return "Running"
        case .restarting: return "Restarting"
        case .paused: return "Paused"
        case .created: return "Created"
        case .dead: return "Dead"
        case .exited(let code): return code.map { "Exited (\($0))" } ?? "Exited"
        case .other(let state): return state.capitalized
        }
    }
    package var failed: Bool {
        switch self {
        case .unhealthy, .restarting, .dead: return true
        case .exited(let code): return code != 0
        default: return false
        }
    }
}
