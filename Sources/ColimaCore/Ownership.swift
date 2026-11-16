import Foundation

// Labels any tool can set on a container to say who created it. The scan
// treats a container whose owner is gone as orphaned.
package enum OwnerLabel {
    // The folder the container was created for, such as a worktree. Read as
    // the container's origin when Compose did not record one.
    package static let workingDirectory = "dev.owner.working_dir"
    // The PID, on this Mac, of the process that created the container.
    package static let pid = "dev.owner.pid"

    package static func pid(in labels: [String: String]) -> Int32? {
        labels[pid].flatMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    // A PID that is missing, malformed or reused reads as alive, so a bad
    // label never makes a container look orphaned.
    package static func processAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return true }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}

// Testcontainers labels the containers it starts with a session ID and starts
// one Ryuk container per session, which removes the session's containers after
// its clients disconnect. Once Ryuk is gone, nothing will remove them.
package enum Testcontainers {
    // Node and others use the first spelling; Java and Go the second.
    package static let sessionLabels = ["org.testcontainers.session-id", "org.testcontainers.sessionId"]
    private static let ryukPrefix = "testcontainers-ryuk-"

    package static func isRyuk(name: String, image: String, labels: [String: String]) -> Bool {
        let repository = image.split(separator: "@").first.map(String.init) ?? image
        let withoutTag =
            repository.range(of: #":[^/]+$"#, options: .regularExpression).map {
                String(repository[..<$0.lowerBound])
            } ?? repository
        return name.hasPrefix(ryukPrefix) || withoutTag == "testcontainers/ryuk"
            || withoutTag.hasSuffix("/testcontainers/ryuk") || labels["org.testcontainers.ryuk"] == "true"
    }
    // Ryuk is named after its session; other containers carry the label.
    package static func session(name: String, labels: [String: String]) -> String? {
        if name.hasPrefix(ryukPrefix), name.count > ryukPrefix.count {
            return String(name.dropFirst(ryukPrefix.count))
        }
        return sessionLabels.lazy.compactMap { labels[$0] }.first { !$0.isEmpty }
    }
    // The project name the list and the scan show for a session. It keeps
    // the whole ID: sessions sharing a prefix must stay apart.
    package static func project(session: String) -> String {
        "testcontainers " + session
    }
    // The Compose project, else the session's project name.
    package static func project(name: String, labels: [String: String]) -> String? {
        labels["com.docker.compose.project"] ?? session(name: name, labels: labels).map(project(session:))
    }

    package enum Reaper { case alive, ownerRunning, gone }
    // A session's own Ryuk decides; a container with an owner PID vouches
    // for a session that runs without Ryuk (the scan has already split off
    // containers whose owner exited).
    package static func reaper(ryukRunning: Bool, hasOwnerPID: Bool) -> Reaper {
        ryukRunning ? .alive : hasOwnerPID ? .ownerRunning : .gone
    }
}
