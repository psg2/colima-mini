import AppKit

// The menu bar item keeps running after the dashboard closes. With the
// default setting, the Dock icon follows the window: shown while it is open,
// hidden once it closes.
@MainActor enum DockIcon {
    static let settingKey = "hideDockWhenClosed"
    static var hidesWhenClosed: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }
    static func windowOpened() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    static func windowClosed() {
        if hidesWhenClosed { NSApp.setActivationPolicy(.accessory) }
    }
}
