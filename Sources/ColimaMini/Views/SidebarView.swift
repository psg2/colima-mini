import AppKit
import ColimaAppState
import SwiftUI

private enum SidebarSelection: Hashable {
    case section(AppRoute)
    case project(String)
}
struct SidebarView: View {
    @ObservedObject var model: Dashboard
    @Environment(\.openSettings) private var openSettings
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
                HStack(spacing: 6) {
                    Circle().fill(model.snapshot?.vm.running == true ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(model.snapshot?.vm.status ?? "Connecting…").fontWeight(.medium)
                    Spacer()
                    if let vm = model.snapshot?.vm {
                        Button(vm.running ? "Stop" : "Start") {
                            model.request(vm.running ? "stop" : "start", containers: [], vm: true)
                        }
                        .controlSize(.small).disabled(model.busy || model.sample)
                        .accessibilityIdentifier(vm.running ? "vm.stop" : "vm.start")
                    }
                }.font(.callout)
                    .help(model.snapshot?.vm.allocation ?? "Default profile")
            }.padding(20)
            List(selection: selection) {
                navigationRow("Overview", symbol: "gauge.with.dots.needle.33percent", route: .overview)
                navigationRow(
                    "Containers", symbol: "shippingbox", route: .containers, count: model.containers.count)
                navigationRow("Images", symbol: "square.3.layers.3d", route: .images)
                navigationRow("Volumes", symbol: "externaldrive", route: .volumes)
                navigationRow(
                    "Networks", symbol: "point.3.connected.trianglepath.dotted", route: .networks)
                navigationRow("Storage", symbol: "chart.pie", route: .storage)
                Section("Projects") {
                    let orphaned = model.orphanedProjects
                    ForEach(model.snapshot?.projects ?? [], id: \.self) { project in
                        let origin = model.origin(of: project)
                        HStack {
                            Label(
                                project,
                                systemImage: project == "Standalone"
                                    ? "shippingbox"
                                    : orphaned.contains(project)
                                        ? "folder.badge.questionmark" : origin?.kind.symbol ?? "folder"
                            )
                            .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if model.containers.contains(where: { $0.project == project && $0.needsAttention }) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                    .font(.caption)
                            }
                            Text("\(model.containers.filter { $0.project == project }.count)")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }.contentShape(Rectangle())
                            .help(origin.map { $0.summary + "\n" + $0.displayPath } ?? project)
                            .tag(SidebarSelection.project(project))
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    if model.canGoBack { model.navigate(.containers, project: project) }
                                })
                    }
                }
            }.listStyle(.sidebar)
            Divider().padding(.horizontal, 16)
            // Settings is its own window (⌘,), as in other Mac apps, not a page.
            Button {
                SettingsOpener(openSettings: openSettings)()
            } label: {
                Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.horizontal, 22).padding(.vertical, 14)
            .help("Settings (⌘,)").accessibilityIdentifier("dashboard.settings")

        }
    }
    private func navigationRow(_ title: String, symbol: String, route: AppRoute, count: Int? = nil)
        -> some View
    {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if let count { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
        }.contentShape(Rectangle()).tag(SidebarSelection.section(route))
            // A detail page keeps its section selected, so a click on that row is no
            // selection change; navigate explicitly to return to the list.
            .simultaneousGesture(
                TapGesture().onEnded {
                    if model.route != route || model.canGoBack {
                        model.navigate(route, project: route == .containers ? "All containers" : nil)
                    }
                })
    }
}
