import AppKit
import ColimaCore

// Editors and terminals the app can hand a project folder or shell to. Only
// installed ones are offered; the user's last choice becomes the default.
struct ExternalApp: Identifiable, Hashable {
    enum Kind { case finder, editor, terminal }
    let id: String
    let name: String
    let url: URL
    let kind: Kind
    var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

@MainActor enum ExternalApps {
    private static let catalog: [(String, String, ExternalApp.Kind)] = [
        ("com.apple.finder", "Finder", .finder),
        ("dev.zed.Zed", "Zed", .editor),
        ("dev.zed.Zed-Preview", "Zed Preview", .editor),
        ("com.microsoft.VSCode", "Visual Studio Code", .editor),
        ("com.todesktop.230313mzl4w4u92", "Cursor", .editor),
        ("com.exafunction.windsurf", "Windsurf", .editor),
        ("com.vscodium", "VSCodium", .editor),
        ("com.sublimetext.4", "Sublime Text", .editor),
        ("com.panic.Nova", "Nova", .editor),
        ("com.jetbrains.intellij", "IntelliJ IDEA", .editor),
        ("com.jetbrains.WebStorm", "WebStorm", .editor),
        ("com.jetbrains.goland", "GoLand", .editor),
        ("com.jetbrains.pycharm", "PyCharm", .editor),
        ("com.apple.dt.Xcode", "Xcode", .editor),
        ("com.cmuxterm.app", "cmux", .terminal),
        ("com.mitchellh.ghostty", "Ghostty", .terminal),
        ("com.googlecode.iterm2", "iTerm", .terminal),
        ("dev.warp.Warp-Stable", "Warp", .terminal),
        ("com.github.wez.wezterm", "WezTerm", .terminal),
        ("net.kovidgoyal.kitty", "kitty", .terminal),
        ("org.alacritty", "Alacritty", .terminal),
        ("com.apple.Terminal", "Terminal", .terminal),
    ]
    private static let folderKey = "folderApp"
    private static let terminalKey = "terminalApp"

    static var installed: [ExternalApp] {
        catalog.compactMap { id, name, kind in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map {
                ExternalApp(id: id, name: name, url: $0, kind: kind)
            }
        }
    }
    static var terminals: [ExternalApp] { installed.filter { $0.kind == .terminal } }

    static var folderDefault: ExternalApp? {
        let apps = installed
        let saved = UserDefaults.standard.string(forKey: folderKey)
        return apps.first { $0.id == saved } ?? apps.first { $0.kind == .editor } ?? apps.first
    }
    static func setFolderDefault(_ app: ExternalApp) {
        UserDefaults.standard.set(app.id, forKey: folderKey)
    }
    static var terminal: ExternalApp? {
        let apps = terminals
        let saved = UserDefaults.standard.string(forKey: terminalKey)
        return apps.first { $0.id == saved } ?? apps.first { $0.id == "com.apple.Terminal" }
            ?? apps.first
    }
    static func setTerminal(_ app: ExternalApp) {
        UserDefaults.standard.set(app.id, forKey: terminalKey)
    }

    static func open(_ folder: URL, with app: ExternalApp) throws {
        switch app.kind {
        case .finder: NSWorkspace.shared.open(folder)
        case .editor:
            NSWorkspace.shared.open(
                [folder], withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
        case .terminal: try run(ShellScript.folder(folder.path), in: app)
        }
    }

    // Terminal, iTerm, cmux and Warp open a .command document; the others take
    // the script as a command-line argument in a new instance.
    static func run(_ script: String, in app: ExternalApp) throws {
        let file = try ShellScript.write(script)
        let arguments: [String]? =
            switch app.id {
            case "com.mitchellh.ghostty", "org.alacritty": ["-e", file.path]
            case "com.github.wez.wezterm": ["start", "--", file.path]
            case "net.kovidgoyal.kitty": [file.path]
            default: nil
            }
        let configuration = NSWorkspace.OpenConfiguration()
        if let arguments {
            configuration.arguments = arguments
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
        } else {
            NSWorkspace.shared.open([file], withApplicationAt: app.url, configuration: configuration)
        }
    }
}
