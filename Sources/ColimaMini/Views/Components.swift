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
  var compact = false
  var body: some View {
    Menu {
      Button("Copy \(port.address)") { Launcher.copy(port.address) }
      if port.protocolName == "tcp" {
        Divider()
        Button("Open as HTTP") { port.url(scheme: "http").map { NSWorkspace.shared.open($0) } }
        Button("Open as HTTPS") { port.url(scheme: "https").map { NSWorkspace.shared.open($0) } }
      }
    } label: {
      Text(compact ? ":\(port.hostPort)" : port.label).font(.system(.caption2, design: .monospaced))
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
  var compact = false
  var body: some View {
    HStack(spacing: 4) {
      ForEach(ports.prefix(limit)) { PortChip(port: $0, compact: compact) }
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
  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
  static func shell(_ container: Container, model: Dashboard) {
    guard !model.sample, container.running else { return }
    guard let terminal = ExternalApps.terminal else {
      model.error = "No terminal app is installed."
      return
    }
    do {
      let docker = try model.backend.toolchain.executable("docker")
      try ExternalApps.run(ShellScript.container(docker: docker, id: container.id), in: terminal)
    } catch { model.error = "Could not open a shell: " + error.localizedDescription }
  }
  static func open(_ origin: ProjectOrigin, with app: ExternalApp, model: Dashboard) {
    ExternalApps.setFolderDefault(app)
    do { try ExternalApps.open(origin.url, with: app) } catch {
      model.error = "Could not open \(app.name): " + error.localizedDescription
    }
  }
  static func openRepository(_ origin: ProjectOrigin, model: Dashboard) {
    Task {
      do {
        guard let url = try await model.backend.repositoryURL(folder: origin.path) else {
          model.error = "\(origin.displayPath) has no origin remote with a web page."
          return
        }
        NSWorkspace.shared.open(url)
      } catch { model.error = "Could not read the Git remote: " + error.localizedDescription }
    }
  }
}

// Folder actions for a Compose project, shared by the list, menu bar and sidebar.
struct OriginMenuItems: View {
  @ObservedObject var model: Dashboard
  let origin: ProjectOrigin
  var body: some View {
    let available = origin.exists() && !model.sample
    if !origin.exists() {
      Text("Folder deleted: " + origin.displayPath)
    }
    let apps = ExternalApps.installed
    let preferred = ExternalApps.folderDefault
    ForEach([preferred].compactMap { $0 } + apps.filter { $0 != preferred }) { app in
      Button {
        Launcher.open(origin, with: app, model: model)
      } label: {
        Label {
          Text(app == preferred ? "\(app.name) (default)" : app.name)
        } icon: {
          Image(nsImage: app.icon)
        }
      }.disabled(!available)
    }
    Divider()
    if FileManager.default.fileExists(atPath: origin.url.appendingPathComponent(".git").path) {
      Button("Open repository in browser") { Launcher.openRepository(origin, model: model) }
        .disabled(!available)
    }
    Button("Copy folder path") { Launcher.copy(origin.path) }
  }
}

// Opens the project folder in the default app with one click; the menu picks
// another app, which becomes the default.
struct OpenFolderButton: View {
  @ObservedObject var model: Dashboard
  let origin: ProjectOrigin
  var body: some View {
    let preferred = ExternalApps.folderDefault
    Menu {
      OriginMenuItems(model: model, origin: origin)
    } label: {
      if let preferred {
        Label {
          Text("Open")
        } icon: {
          Image(nsImage: preferred.icon)
        }
      } else {
        Label("Open", systemImage: "folder")
      }
    } primaryAction: {
      if let preferred, origin.exists(), !model.sample {
        Launcher.open(origin, with: preferred, model: model)
      }
    }
    .fixedSize()
    .help(
      origin.exists()
        ? "Open \(origin.displayPath)" + (preferred.map { " in \($0.name)" } ?? "")
        : "Folder deleted: \(origin.displayPath)")
  }
}
