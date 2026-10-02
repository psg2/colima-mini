import Foundation

package struct Fixture: Decodable {
  package let vm: String
  package let containers: String
  package let stats: String
  package let logs: [String: String]?
  package let sweep: String?
  package var snapshot: Snapshot {
    get throws { try Snapshot.decode(vm: vm, containers: containers, stats: stats) }
  }
}
