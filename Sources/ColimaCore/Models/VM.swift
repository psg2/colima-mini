import Foundation

package struct VM: Decodable {
    package let name: String
    package let status: String
    package let cpus: Int
    package let memory: Int64
    package var disk: Int64? = nil
    package var arch: String? = nil
    package var runtime: String? = nil
    package var running: Bool { status.lowercased() == "running" }
    package var allocation: String {
        let memory = String(format: "%g", Double(memory) / 1_073_741_824)
        let disk = disk.map { " · \(String(format: "%g", Double($0) / 1_073_741_824)) GiB disk" } ?? ""
        return "\(cpus) CPUs · \(memory) GiB" + disk
    }
}
