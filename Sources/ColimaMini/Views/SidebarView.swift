import AppKit
import ColimaAppState
import SwiftUI

private enum SidebarSelection: Hashable {
  case section(AppRoute)
  case project(String)
}
struct SidebarView: View {
  @ObservedObject var model: Dashboard
  private var selection: Binding<SidebarSelection?> {
    Binding(
      get: {
        model.route.section == .containers && model.project != "All containers"
          ? .project(model.project) : .section(model.route.section)
      },
      set: { selection in
        switch selection {
        case .project(let project): model.navigate(.containers, project: project)
        case .section(let route):
          model.navigate(route, project: route == .containers ? "All containers" : nil)
        case nil: break
        }
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 9) {
          if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon).resizable().frame(width: 30, height: 30)
          }
          Text("Colima Mini").font(.system(.title3, design: .rounded).weight(.semibold))
        }
        Label(model.snapshot?.vm.status ?? "Connecting…", systemImage: "circle.fill")
          .font(.caption).foregroundStyle(model.snapshot?.vm.running == true ? .teal : .secondary)
        Text(model.snapshot?.vm.allocation ?? "Default profile").font(.caption).foregroundStyle(
          .secondary)
        HStack {
          Button("Start") { model.request("start", containers: [], vm: true) }
            .disabled(model.snapshot?.vm.running != false || model.busy || model.sample)
            .accessibilityIdentifier("vm.start")
          Button("Stop") { model.request("stop", containers: [], vm: true) }
            .disabled(model.snapshot?.vm.running != true || model.busy || model.sample)
            .accessibilityIdentifier("vm.stop")
        }
      }.padding(20)
      List(selection: selection) {
        navigationRow(
          "Containers", symbol: "shippingbox", route: .containers, count: model.containers.count)
        navigationRow("Volumes", symbol: "externaldrive", route: .volumes)
        navigationRow("Images", symbol: "square.3.layers.3d", route: .images)
        navigationRow("Storage", symbol: "chart.pie", route: .storage)
        Section("Projects") {
          ForEach(model.snapshot?.projects ?? [], id: \.self) { project in
            HStack {
              Label(project, systemImage: project == "Standalone" ? "shippingbox" : "folder")
                .lineLimit(1).truncationMode(.middle)
              Spacer()
              Text("\(model.containers.filter { $0.project == project }.count)")
                .foregroundStyle(.secondary).monospacedDigit()
            }.tag(SidebarSelection.project(project))
          }
        }
      }.listStyle(.sidebar)
      Divider().padding(.horizontal, 16)
      List(selection: selection) {
        Label("Settings", systemImage: "gearshape")
          .tag(SidebarSelection.section(.settings))
          .accessibilityIdentifier("dashboard.settings")
      }.listStyle(.sidebar).scrollDisabled(true).frame(height: 48)

    }
  }
  private func navigationRow(_ title: String, symbol: String, route: AppRoute, count: Int? = nil)
    -> some View
  {
    HStack {
      Label(title, systemImage: symbol)
      Spacer()
      if let count { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
    }.tag(SidebarSelection.section(route))
  }
}
