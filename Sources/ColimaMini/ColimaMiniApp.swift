import AppKit
import ColimaCore
import Foundation
import SwiftUI

@main struct ColimaMiniApp: App {
  @StateObject private var model: Dashboard
  private let sample: Bool
  init() {
    do {
      if CommandLine.arguments.contains("--help") {
        print(
          """
          Colima Mini — native macOS dashboard for the default Colima profile.

          Usage: ColimaMini [--check | --scan] [--fixture SNAPSHOT_JSON]
            --check    Print a read-only JSON runtime summary without opening a window.
            --scan     Print the unused-container report without applying cleanup.
            --fixture  Read synthetic sample data; runtime actions are disabled.
            --help     Show this help.
          """)
        exit(0)
      }
      let fixture = try Self.fixtureArgument()
      sample = fixture != nil
      _model = StateObject(wrappedValue: Dashboard(backend: Backend(fixture: fixture)))
      if CommandLine.arguments.contains("--check") || CommandLine.arguments.contains("--scan") {
        Task {
          do {
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
      .commands { CommandGroup(replacing: .newItem) {} }
    Settings { SettingsView(model: model) }
    MenuBarExtra {
      MenuView(model: model)
    } label: {
      Image(nsImage: llamaMenuIcon).accessibilityLabel("Colima Mini")
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
