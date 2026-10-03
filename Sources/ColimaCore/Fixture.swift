import Foundation

package struct Fixture: Decodable {
    package let vm: String
    package let containers: String
    package let stats: String
    package let logs: [String: String]?
    package let sweep: String?
    package var sweepGroups: [SweepGroup]? = nil
    package var environment: [String: [String]]? = nil
    package var networks: [DockerNetwork]? = nil
    package var details: [String: ContainerDetails]? = nil
    package var volumes: [Volume]? = nil
    package var images: [DockerImage]? = nil
    package var storage: StorageSnapshot? = nil
    package var snapshot: Snapshot {
        get throws { try Snapshot.decode(vm: vm, containers: containers, stats: stats) }
    }
}
