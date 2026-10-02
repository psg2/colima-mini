import AppKit
import ColimaAppState
import ColimaCore
import Foundation
import SwiftUI

@main struct ColimaMiniApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model: Dashboard
  private let sample: Bool
  init() {
    do {
      if CommandLine.arguments.contains("--help") {
        print(
          """
          Colima Mini — native macOS dashboard for the default Colima profile.

          Usage: ColimaMini [--check | --scan | --reclaim-plan] [--fixture SNAPSHOT_JSON]
            --check    Print a read-only JSON runtime summary without opening a window.
            --scan     Print the unused-container report without applying cleanup.
            --reclaim-plan
                       Print what Reclaim space would offer to remove, without removing it.
            --fixture  Read synthetic sample data; runtime actions are disabled.
            --help     Show this help.
          """)
        exit(0)
      }
      let fixture = try Self.fixtureArgument()
      sample = fixture != nil
      let dashboard = Dashboard(backend: Backend(fixture: fixture))
      dashboard.restoreLastSection()
      _model = StateObject(wrappedValue: dashboard)
      if ["--check", "--scan", "--reclaim-plan"].contains(where: CommandLine.arguments.contains) {
        Task {
          do {
            if CommandLine.arguments.contains("--reclaim-plan") {
              let plan = try await Backend(fixture: fixture).cleanupPlan()
              for category in plan.categories {
                print(
                  "\(category.kind.title): \(category.items.count) items, \(Int(category.bytes)) bytes"
                    + (category.kind.safeByDefault ? " (selected by default)" : ""))
              }
              exit(0)
            }
            if CommandLine.arguments.contains("--scan") {
              print(try await Backend(fixture: fixture).sweep())
              exit(0)
            }
            let snapshot = try await Backend(fixture: fixture).snapshot()
            let data = try JSONSerialization.data(
              withJSONObject: snapshot.summary, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            exit(0)
          } catch {
            fputs(error.localizedDescription + "\n", stderr)
            exit(1)
          }
        }
        dispatchMain()
      }
    } catch {
      fputs(error.localizedDescription + "\n", stderr)
      exit(1)
    }
  }
  var body: some Scene {
    Window(sample ? "Colima Mini · Sample data" : "Colima Mini", id: "dashboard") {
      DashboardView(model: model).frame(minWidth: 920, minHeight: 580)
    }.defaultSize(width: 1120, height: 740)
      .commands {
        CommandGroup(replacing: .newItem) {}
        AppCommands(model: model)
      }
    Settings { SettingsView(model: model, tabbed: true) }
    MenuBarExtra {
      MenuView(model: model)
    } label: {
      MenuBarLabel(model: model)
    }.menuBarExtraStyle(.window)
  }
  static func fixtureArgument() throws -> Fixture? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: "--fixture") else { return nil }
    guard args.indices.contains(index + 1) else {
      throw AppError.message("Usage: --fixture path/to/snapshot.json")
    }
    return try JSONDecoder().decode(
      Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: args[index + 1])))
  }
}

// The label lives for the whole app session, so it owns the refresh loop and
// the window opener used by notifications.
struct MenuBarLabel: View {
  @ObservedObject var model: Dashboard
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    let attention = model.attention.count
    HStack(spacing: 3) {
      Image(nsImage: model.snapshot?.vm.running == false ? llamaMenuIconDimmed : llamaMenuIcon)
      if attention > 0 { Text("\(attention)").monospacedDigit() }
    }
    .accessibilityLabel(
      attention > 0 ? "Colima Mini, \(attention) containers need attention" : "Colima Mini"
    )
    .task {
      Notifier.shared.attach(to: model) { id in
        model.openContainer(id, tab: .logs)
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
      }
      await model.poll { NSApp.isActive }
    }
  }
}
