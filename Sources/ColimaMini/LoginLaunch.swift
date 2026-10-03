import AppKit

// A launch at login starts in the menu bar only; opening the app by hand still
// shows the dashboard. SwiftUI opens the window before the app can tell, so it
// is closed again once launching finishes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        guard event?.eventID == kAEOpenApplication,
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        else { return }
        DispatchQueue.main.async {
            for window in NSApp.windows
            where window.identifier?.rawValue.hasPrefix("dashboard") == true {
                window.close()
            }
            DockIcon.windowClosed()
        }
    }
}
