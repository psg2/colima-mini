import ColimaAppState
import ColimaCore
import SwiftUI

// Menu bar commands, so every shortcut is discoverable from the Go and
// Container menus. Actions that change containers still confirm first.
struct AppCommands: Commands {
  @ObservedObject var model: Dashboard
  var body: some Commands {
    CommandGroup(after: .textEditing) {
      Button("Find") { model.findRequest += 1 }.keyboardShortcut("f")
    }
    CommandMenu("Go") {
      Button("Overview") { model.navigate(.overview) }.keyboardShortcut("1")
      Button("Containers") { model.navigate(.containers, project: "All containers") }
        .keyboardShortcut("2")
      Button("Images") { model.navigate(.images) }.keyboardShortcut("3")
      Button("Volumes") { model.navigate(.volumes) }.keyboardShortcut("4")
      Button("Networks") { model.navigate(.networks) }.keyboardShortcut("5")
      Button("Storage") { model.navigate(.storage) }.keyboardShortcut("6")
      Divider()
      Button("Back") { model.goBack() }.keyboardShortcut("[").disabled(!model.canGoBack)
      Button("Search and Actions…") { model.showingPalette = true }.keyboardShortcut("k")
      Divider()
      Button("Reclaim Space…") { model.openReclaim() }
        .disabled(model.busy || model.sample || model.snapshot?.vm.running != true)
      Button("Review Unused Containers…") { Task { await model.scan() } }
        .disabled(model.scanning || model.busy || model.snapshot?.vm.running != true)
    }
    CommandMenu("Container") {
      let container = model.openContainer
      ForEach(Array(ContainerPageTab.allCases.enumerated()), id: \.element) { index, tab in
        Button(tab == .environment ? "Environment" : tab.rawValue) { model.containerTab = tab }
          .keyboardShortcut(
            KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option]
          )
          .disabled(container == nil)
      }
      Divider()
      Button("Open Shell") { container.map { Launcher.shell($0, model: model) } }
        .keyboardShortcut("t", modifiers: [.command, .shift])
        .disabled(container?.running != true || model.sample)
      Button("Open Project Folder") {
        if let origin = folderOrigin, let app = ExternalApps.folderDefault {
          Launcher.open(origin, with: app, model: model)
        }
      }
      .keyboardShortcut("o", modifiers: [.command, .shift])
      .disabled(folderOrigin?.exists() != true || model.sample)
      Divider()
      Button(container?.running == false ? "Start…" : "Stop…") {
        if let container {
          model.request(container.running ? "stop" : "start", containers: [container])
        }
      }
      .keyboardShortcut("s", modifiers: [.command, .shift])
      .disabled(container == nil || model.busy || model.sample)
      Button("Restart…") { container.map { model.request("restart", containers: [$0]) } }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(container?.running != true || model.busy || model.sample)
      Button("Remove…") { container.map { model.request("rm", containers: [$0]) } }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(container == nil || container?.running == true || model.busy || model.sample)
    }
  }
  // The open container's project folder, or the project page's.
  private var folderOrigin: ProjectOrigin? {
    if let container = model.openContainer { return container.origin }
    if model.route == .containers, model.project != "All containers" {
      return model.visible.lazy.compactMap(\.origin).first
    }
    return nil
  }
}

extension View {
  // Lets Find (⌘F) focus this field while it is on screen.
  func findable(_ model: Dashboard) -> some View { modifier(Findable(model: model)) }
}

private struct Findable: ViewModifier {
  @ObservedObject var model: Dashboard
  @FocusState private var focused: Bool
  func body(content: Content) -> some View {
    content.focused($focused).onChange(of: model.findRequest) { _, _ in focused = true }
  }
}
