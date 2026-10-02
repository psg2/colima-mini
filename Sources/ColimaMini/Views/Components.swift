import AppKit
import ColimaAppState
import ColimaCore
import SwiftUI

extension ContainerCondition {
  var color: Color {
    switch self {
    case .healthy, .running: return .green
    case .starting: return .teal
    case .exited(let code) where code == 0: return .secondary
    case .unhealthy, .restarting, .dead, .exited: return .orange
    case .paused, .created, .other: return .secondary
    }
  }
}

struct ConditionPill: View {
  let condition: ContainerCondition
  var body: some View {
    HStack(spacing: 5) {
      Circle().fill(condition.color).frame(width: 6, height: 6)
      Text(condition.title).lineLimit(1)
    }
    .font(.caption.weight(.medium)).foregroundStyle(condition.color)
    .padding(.horizontal, 7).padding(.vertical, 3)
    .background(condition.color.opacity(0.13), in: Capsule())
  }
}

// TCP doesn't identify HTTP, so the chip copies the address and opening a
// browser stays an explicit protocol choice.
struct PortChip: View {
  let port: PublishedPort
  var body: some View {
    Menu {
      Button("Copy \(port.address)") { Launcher.copy(port.address) }
      if port.protocolName == "tcp" {
        Divider()
        Button("Open as HTTP") { port.url(scheme: "http").map { NSWorkspace.shared.open($0) } }
        Button("Open as HTTPS") { port.url(scheme: "https").map { NSWorkspace.shared.open($0) } }
      }
    } label: {
      Text(port.label).font(.system(.caption2, design: .monospaced))
    } primaryAction: {
      Launcher.copy(port.address)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .padding(.horizontal, 6).padding(.vertical, 2)
    .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    .help(
      "Click to copy \(port.address). Host \(port.hostPort) → container \(port.containerPort)/\(port.protocolName)"
    )
    .accessibilityLabel("Port \(port.label)")
  }
}

struct PortChips: View {
  let ports: [PublishedPort]
  var limit = 3
  var body: some View {
    HStack(spacing: 4) {
      ForEach(ports.prefix(limit)) { PortChip(port: $0) }
      if ports.count > limit {
        Text("+\(ports.count - limit)").font(.caption2).foregroundStyle(.secondary)
          .help(ports.dropFirst(limit).map(\.label).joined(separator: ", "))
      }
    }
  }
}

extension ProjectOrigin.Kind {
  var symbol: String {
    switch self {
    case .folder: return "folder"
    case .claude, .codex, .conductor, .orca: return "arrow.triangle.branch"
    }
  }
}

@MainActor enum Launcher {
  private static let editors = [
    ("Visual Studio Code", "com.microsoft.VSCode"), ("Cursor", "com.todesktop.230313mzl4w4u92"),
    ("Zed", "dev.zed.Zed"),
  ]
  static var editor: (name: String, url: URL)? {
    for (name, identifier) in editors {
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
        return (name, url)
      }
    }
    return nil
  }
  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
  static func shell(_ container: Container, model: Dashboard) {
    guard !model.sample, container.running else { return }
    do {
      let docker = try model.backend.toolchain.executable("docker")
      NSWorkspace.shared.open(
        try ShellScript.write(ShellScript.container(docker: docker, id: container.id)))
    } catch { model.error = "Could not open a shell: " + error.localizedDescription }
  }
  static func terminal(_ folder: URL, model: Dashboard) {
    do {
      NSWorkspace.shared.open(try ShellScript.write(ShellScript.folder(folder.path)))
    } catch { model.error = "Could not open Terminal: " + error.localizedDescription }
  }
  static func edit(_ folder: URL) {
    guard let editor else { return }
    NSWorkspace.shared.open(
      [folder], withApplicationAt: editor.url, configuration: NSWorkspace.OpenConfiguration())
  }
}

// Folder actions for a Compose project, shared by the list, menu bar and sidebar.
struct OriginMenuItems: View {
  @ObservedObject var model: Dashboard
  let origin: ProjectOrigin
  var body: some View {
    let available = origin.exists() && !model.sample
    Button("Open in Finder") { NSWorkspace.shared.open(origin.url) }.disabled(!available)
    Button("Open in Terminal") { Launcher.terminal(origin.url, model: model) }
      .disabled(!available)
    if let editor = Launcher.editor {
      Button("Open in \(editor.name)") { Launcher.edit(origin.url) }.disabled(!available)
    }
    Button("Copy folder path") { Launcher.copy(origin.path) }
  }
}
