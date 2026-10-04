import Foundation

// Finds containers nobody is using. Containers are grouped by Compose project
// (standalone containers are their own group) and each group gets one verdict:
//
//   orphan   its Compose folder no longer exists (a deleted worktree)
//   active   a host process is connected to a published port, or the
//            containers sent or received traffic during the sample
//   idle     running, but nothing connected, no traffic and no log line for
//            at least `idleFor`
//   recent   running and quiet, but logged something within `idleFor`
//   stale    not running for at least `idleFor`
//   stopped  not running, but stopped within `idleFor`
//
// The scan only reads; acting on a verdict is up to the user.
package enum UnusedContainerScan {
    // What `docker inspect` reports about one container.
    package struct Inspected: Decodable {
        package let id: String
        package let name: String
        let created: Date?
        let running: Bool
        let startedAt: Date?
        let finishedAt: Date?
        let labels: [String: String]
        let hostPorts: [String]

        private struct State: Decodable {
            let running: Bool
            let startedAt: String?
            let finishedAt: String?
            enum CodingKeys: String, CodingKey {
                case running = "Running", startedAt = "StartedAt", finishedAt = "FinishedAt"
            }
        }
        private struct Config: Decodable {
            let labels: [String: String]?
            enum CodingKeys: String, CodingKey { case labels = "Labels" }
        }
        private struct Binding: Decodable {
            let hostPort: String?
            enum CodingKeys: String, CodingKey { case hostPort = "HostPort" }
        }
        private struct NetworkSettings: Decodable {
            let ports: [String: [Binding]?]?
            enum CodingKeys: String, CodingKey { case ports = "Ports" }
        }
        private enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", created = "Created", state = "State", config = "Config"
            case networkSettings = "NetworkSettings"
        }

        package init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let state = try values.decode(State.self, forKey: .state)
            let network = try values.decodeIfPresent(NetworkSettings.self, forKey: .networkSettings)
            id = try values.decode(String.self, forKey: .id)
            name = String(try values.decode(String.self, forKey: .name).drop { $0 == "/" })
            created = DockerDate.parse(try values.decodeIfPresent(String.self, forKey: .created))
            running = state.running
            startedAt = DockerDate.parse(state.startedAt)
            finishedAt = DockerDate.parse(state.finishedAt)
            labels = try values.decode(Config.self, forKey: .config).labels ?? [:]
            hostPorts = (network?.ports ?? [:]).values.flatMap { $0 ?? [] }.compactMap(\.hostPort)
        }

        var project: String? { labels["com.docker.compose.project"] }
        var workingDirectory: String? { labels["com.docker.compose.project.working_dir"] }
    }

    // Published host port -> processes on the Mac connected to it, from
    // `lsof -nP -iTCP -sTCP:ESTABLISHED`. Docker's own side of each forwarded
    // connection is not a client.
    package static func hostClients(lsof output: String) -> [String: [String]] {
        var clients: [String: [String]] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.count >= 9,
                !["com.docke", "vpnkit", "docker"].contains(where: fields[0].hasPrefix),
                let connection = fields.first(where: { $0.contains("->") }),
                let remote = connection.components(separatedBy: "->").last,
                let port = remote.split(separator: ":").last
            else { continue }
            let client = "\(fields[0])(\(fields[1]))"
            if !(clients[String(port)] ?? []).contains(client) { clients[String(port), default: []].append(client) }
        }
        return clients
    }

    // Container ID -> network I/O, from `docker stats --no-stream`.
    package static func networkIO(stats output: String) -> [String: String] {
        var io: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            if parts.count == 2 { io[parts[0]] = parts[1] }
        }
        return io
    }

    // Short IDs of containers whose network I/O changed between two samples.
    package static func traffic(before: [String: String], after: [String: String]) -> Set<String> {
        Set(after.compactMap { id, io in before[id].map { $0 != io } == true ? String(id.prefix(12)) : nil })
    }

    // `lastLog` returns the time of a running container's newest log line.
    package static func classify(
        _ containers: [Inspected], clients: [String: [String]], traffic: Set<String>,
        idleFor: TimeInterval = 86_400, now: Date = Date(),
        folderExists: (String) -> Bool = { ProjectOrigin(path: $0).exists() },
        lastLog: (String) async throws -> Date?
    ) async rethrows -> [SweepGroup] {
        var order: [String] = []
        var members: [String: [Inspected]] = [:]
        for container in containers {
            let key = container.project ?? container.name
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(container)
        }
        var groups: [SweepGroup] = []
        for key in order {
            let group = members[key] ?? []
            let (verdict, reason) = try await judge(
                group, clients: clients, traffic: traffic, idleFor: idleFor, now: now,
                folderExists: folderExists, lastLog: lastLog)
            groups.append(
                SweepGroup(
                    verdict: verdict, name: key, project: group[0].project, reason: reason,
                    containerIDs: group.map(\.id)))
        }
        let rank = Dictionary(uniqueKeysWithValues: SweepVerdict.allCases.enumerated().map { ($1, $0) })
        return groups.sorted { (rank[$0.verdict]!, $0.name) < (rank[$1.verdict]!, $1.name) }
    }

    private static func judge(
        _ group: [Inspected], clients: [String: [String]], traffic: Set<String>, idleFor: TimeInterval,
        now: Date, folderExists: (String) -> Bool, lastLog: (String) async throws -> Date?
    ) async rethrows -> (SweepVerdict, String) {
        if let folder = group[0].workingDirectory, !folderExists(folder) {
            return (.orphan, "folder gone: \(folder)")
        }
        let running = group.filter(\.running)
        if running.isEmpty {
            // A container created but never started has no finish time.
            let stoppedAt = group.compactMap { $0.finishedAt ?? $0.created }.max() ?? now
            let stoppedFor = now.timeIntervalSince(stoppedAt)
            return stoppedFor >= idleFor
                ? (.stale, "not running for \(duration(stoppedFor))")
                : (.stopped, "stopped \(duration(stoppedFor)) ago")
        }
        var connected: [String] = []
        for client in running.flatMap(\.hostPorts).flatMap({ clients[$0] ?? [] }) where !connected.contains(client) {
            connected.append(client)
        }
        if !connected.isEmpty { return (.active, "clients: " + connected.sorted().joined(separator: " ")) }
        if running.contains(where: { traffic.contains(String($0.id.prefix(12))) }) {
            return (.active, "network traffic during sample")
        }
        var latest = Date.distantPast
        for container in running {
            let candidates = [try await lastLog(container.id), container.startedAt].compactMap { $0 }
            latest = max(latest, candidates.max() ?? .distantPast)
        }
        let quietFor = now.timeIntervalSince(latest)
        return quietFor >= idleFor
            ? (.idle, "no clients, no traffic, quiet for \(duration(quietFor))")
            : (.recent, "no clients, no traffic, last log \(duration(quietFor)) ago")
    }

    // The plain-text report printed by `--scan`.
    package static func report(_ groups: [SweepGroup]) -> String {
        guard !groups.isEmpty else { return "No containers." }
        var lines = groups.map { group in
            let count = group.containerIDs.count
            let name = group.name + (count > 1 ? " (\(count))" : "")
            return group.verdict.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0) + " "
                + name.padding(toLength: max(50, name.count), withPad: " ", startingAt: 0) + " " + group.reason
        }
        let removable = groups.filter { [.orphan, .stale].contains($0.verdict) }.count
        let idle = groups.filter { $0.verdict == .idle }.count
        lines.append("")
        lines.append(
            removable + idle == 0
                ? "Nothing to clean up."
                : "\(removable) orphan or stale group(s) can be removed and \(idle) idle group(s) stopped.")
        return lines.joined(separator: "\n")
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let seconds = Int(seconds)
        if seconds >= 86_400 { return "\(seconds / 86_400)d" }
        if seconds >= 3_600 { return "\(seconds / 3_600)h" }
        return "\(seconds / 60)m"
    }
}
