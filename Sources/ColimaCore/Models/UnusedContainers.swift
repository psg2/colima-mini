import Foundation

// The scanner groups containers by Compose project (standalone containers are
// their own group) and gives each group one verdict.
package enum SweepVerdict: String, Decodable, CaseIterable {
    case orphan, stale, idle, recent, active, stopped
    package var title: String {
        switch self {
        case .orphan: return "Project folder deleted"
        case .stale: return "Stopped for over a day"
        case .idle: return "Running but idle"
        case .recent: return "Quiet, logged recently"
        case .active: return "In use"
        case .stopped: return "Stopped recently"
        }
    }
    package var explanation: String {
        switch self {
        case .orphan:
            return "Its Compose folder no longer exists, usually a deleted worktree. Stop and remove it."
        case .stale:
            return "Removing it keeps its volumes; `docker compose up` recreates the containers."
        case .idle:
            return "No client, no traffic and no log line for a day. Stopping it frees CPU and memory."
        case .recent: return "Nothing connected, but it logged within the last day."
        case .active: return "A process on your Mac is connected, or it had network traffic."
        case .stopped: return "Stopped within the last day."
        }
    }
    // Groups the scanner suggests acting on; the others are listed as kept.
    package var suggested: Bool { [.orphan, .stale, .idle].contains(self) }
}

package struct SweepGroup: Decodable, Identifiable, Equatable {
    package let verdict: SweepVerdict
    package let name: String
    package let project: String?
    package let reason: String
    package let containerIDs: [String]
    package var id: String { name }
    package init(
        verdict: SweepVerdict, name: String, project: String?, reason: String, containerIDs: [String]
    ) {
        self.verdict = verdict
        self.name = name
        self.project = project
        self.reason = reason
        self.containerIDs = containerIDs
    }
    private enum CodingKeys: String, CodingKey {
        case verdict, name, project, reason
        case containerIDs = "containers"
    }
}
