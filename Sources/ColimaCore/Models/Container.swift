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
  package var needsAttention: Bool {
    state == "restarting" || status.contains("unhealthy")
      || (state == "exited" && !status.contains("Exited (0)"))
  }
  package var folder: URL? {
    label("com.docker.compose.project.working_dir").map { URL(fileURLWithPath: $0) }
  }
  package var endpoints: [URL] {
    let regex = try! NSRegularExpression(
      pattern: #"(?:^|,\s*)(?:127\.0\.0\.1|0\.0\.0\.0|\[::\]|\[::1\]):(\d+)->(\d+)/tcp"#)
    let text = ports as NSString
    var seen = Set<String>()
    return regex.matches(in: ports, range: NSRange(location: 0, length: text.length)).compactMap {
      match in
      let port = text.substring(with: match.range(at: 1))
      guard seen.insert(port).inserted else { return nil }
      let scheme = text.substring(with: match.range(at: 2)) == "443" ? "https" : "http"
      return URL(string: "\(scheme)://localhost:\(port)")
    }
  }
}
