import AppKit
import ColimaAppState
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct MenuView: View {
  @ObservedObject var model: Dashboard
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  private func showDashboard(project: String? = nil) {
    if let project {
      model.navigate(.containers, project: project)
    }
    if project == nil { model.navigate(.containers, project: "All containers") }
    openWindow(id: "dashboard")
    NSApp.activate(ignoringOtherApps: true)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        if let icon = NSApp.applicationIconImage {
          Image(nsImage: icon).resizable().frame(width: 44, height: 44)
        }
        VStack(alignment: .leading, spacing: 3) {
          Text("Colima Mini").font(.headline)
          HStack(spacing: 5) {
            Circle().fill(model.snapshot?.vm.running == true ? Color.green : Color.secondary)
              .frame(width: 6, height: 6)
            Text(model.snapshot?.vm.status ?? "Connecting…")
            if model.sample { Text("Sample").foregroundStyle(.orange) }
          }.font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          Task { await model.refresh() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }.help("Refresh").accessibilityIdentifier("menu.refresh")
          .disabled(model.refreshing || model.busy)
      }
      Text(model.snapshot?.vm.allocation ?? "Default profile")
        .font(.caption).foregroundStyle(.secondary)
      if let snapshot = model.snapshot {
        HStack {
          Label(
            "\(snapshot.containers.filter(\.running).count) running", systemImage: "shippingbox")
          Spacer()
          Text("\(snapshot.containers.filter { !$0.running }.count) stopped")
        }.font(.callout).monospacedDigit()
      }
      if let error = model.error {
        Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3)
      }
      Divider()
      if let projects = model.snapshot?.projects, !projects.isEmpty {
        Text("Projects").font(.caption).foregroundStyle(.secondary)
        ScrollView {
          VStack(spacing: 6) {
            ForEach(projects, id: \.self) { project in
              Button {
                showDashboard(project: project)
              } label: {
                HStack {
                  Image(systemName: project == "Standalone" ? "shippingbox" : "folder")
                  Text(project).lineLimit(1).truncationMode(.middle)
                  Spacer()
                  Text(
                    "\(model.containers.filter { $0.project == project && $0.running }.count)/\(model.containers.filter { $0.project == project }.count)"
                  )
                  .foregroundStyle(.secondary).monospacedDigit()
                }.frame(maxWidth: .infinity, alignment: .leading)
              }.help("Open \(project) · running/total containers")
            }
          }
        }.frame(height: min(CGFloat(projects.count) * 30, 180))
        Divider()
      }
      Button("Open dashboard") { showDashboard() }
        .frame(maxWidth: .infinity).accessibilityIdentifier("menu.dashboard")
      Button("Unused containers…") {
        showDashboard()
        Task { await model.scan() }
      }.disabled(model.scanning || model.busy || model.snapshot?.vm.running != true)
        .accessibilityIdentifier("menu.sweep")
      Button("Settings…") {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
      }
      .accessibilityIdentifier("menu.settings")
      Divider()
      HStack {
        Text("Context: colima").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }.accessibilityIdentifier("menu.quit")
      }
    }.padding(16).frame(width: 320)
      .task {
        while !Task.isCancelled {
          await model.refresh()
          try? await Task.sleep(for: .seconds(model.refreshInterval))
        }
      }
  }
}
