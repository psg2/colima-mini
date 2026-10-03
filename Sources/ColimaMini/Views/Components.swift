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
// browser stays an explicit protocol choice, except for images known to serve
// a web page on that port, where a click opens it.
struct PortChip: View {
    let port: PublishedPort
    var compact = false
    var web = false
    var body: some View {
        Menu {
            Button("Copy \(port.address)") { Launcher.copy(port.address) }
            if port.protocolName == "tcp" {
                Divider()
                Button("Open as HTTP") { if let url = port.url(scheme: "http") { NSWorkspace.shared.open(url) } }
                Button("Open as HTTPS") { if let url = port.url(scheme: "https") { NSWorkspace.shared.open(url) } }
            }
        } label: {
            HStack(spacing: 2) {
                Text(compact ? ":\(port.hostPort)" : port.label)
                if web { Image(systemName: "arrow.up.right") }
            }.font(.system(.caption2, design: .monospaced))
        } primaryAction: {
            if web, let url = port.url(scheme: "http") {
                NSWorkspace.shared.open(url)
            } else {
                Launcher.copy(port.address)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
        .help(
            (web ? "Click to open http://\(port.address)" : "Click to copy \(port.address)")
                + ". Host \(port.hostPort) → container \(port.containerPort)/\(port.protocolName)"
        )
        .accessibilityLabel("Port \(port.label)")
    }
}

struct PortChips: View {
    let ports: [PublishedPort]
    var limit = 3
    var compact = false
    var profile: ImageProfile? = nil
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ports.prefix(limit)) {
                PortChip(port: $0, compact: compact, web: profile?.opensInBrowser($0) == true)
            }
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

// SF Symbols per image category, so rows are recognizable without fetching logos.
struct ImageIcon: View {
    let profile: ImageProfile
    private var style: (String, Color) {
        switch profile.category {
        case .database: return ("cylinder.split.1x2", .blue)
        case .cache: return ("bolt.horizontal", .red)
        case .search: return ("magnifyingglass", .yellow)
        case .queue: return ("tray.2", .orange)
        case .storage: return ("archivebox", .teal)
        case .cloud: return ("cloud", .cyan)
        case .webServer: return ("globe", .green)
        case .webTool: return ("macwindow", .purple)
        case .runtime: return ("chevron.left.forwardslash.chevron.right", .indigo)
        case .other: return ("shippingbox", .secondary)
        }
    }
    var body: some View {
        let (symbol, color) = style
        Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            .frame(width: 22, height: 22)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
    }
}

// Like Open: one click uses the default terminal, and the menu picks another
// terminal, which becomes the default.
struct ShellButton: View {
    @ObservedObject var model: Dashboard
    let container: Container
    var body: some View {
        let preferred = ExternalApps.terminal
        Menu {
            ForEach(ExternalApps.terminals) { app in
                Button {
                    ExternalApps.setTerminal(app)
                    Launcher.shell(container, model: model)
                } label: {
                    Label {
                        Text(app == preferred ? "\(app.name) (default)" : app.name)
                    } icon: {
                        Image(nsImage: app.icon)
                    }
                }
            }
            Divider()
            Button("Copy docker exec command") {
                Launcher.copy("docker --context colima exec -it \(container.name) sh")
            }
        } label: {
            if let preferred {
                Label {
                    Text("Shell")
                } icon: {
                    Image(nsImage: preferred.icon)
                }
            } else {
                Label("Shell", systemImage: "terminal")
            }
        } primaryAction: {
            Launcher.shell(container, model: model)
        }
        .fixedSize().disabled(model.sample)
        .help("Open a shell in \(container.name)" + (preferred.map { " using \($0.name)" } ?? ""))
        .accessibilityIdentifier("container.shell")
    }
}
