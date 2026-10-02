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
  @State private var expanded: Set<String> = []
  private func showDashboard() {
    openWindow(id: "dashboard")
    NSApp.activate(ignoringOtherApps: true)
  }
  private func show(project: String) {
    model.navigate(.containers, project: project)
    showDashboard()
  }
  private func show(_ container: Container, tab: ContainerPageTab = .overview) {
    model.navigate(.containers, project: "All containers")
    model.openContainer(container.id, tab: tab)
    showDashboard()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if let snapshot = model.snapshot, snapshot.vm.running {
        usage(snapshot)
      }
      if let error = model.error {
        Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3)
      }
      if !model.attention.isEmpty {
        Divider()
        attention
      }
      if let projects = model.snapshot?.projects, !projects.isEmpty {
        Divider()
        Text("Projects").font(.caption).foregroundStyle(.secondary)
        ScrollView {
          VStack(spacing: 4) {
            ForEach(projects, id: \.self) { project($0) }
          }
        }.frame(maxHeight: 320).fixedSize(horizontal: false, vertical: true)
      }
      Divider()
      HStack {
        Button("Open dashboard") {
          model.navigate(.containers, project: "All containers")
          showDashboard()
        }.keyboardShortcut("d").accessibilityIdentifier("menu.dashboard")
        Spacer()
        Button {
          model.navigate(.storage)
          showDashboard()
          Task { await model.scan() }
        } label: {
          Image(systemName: "sparkles.rectangle.stack")
        }.help("Review unused containers")
          .disabled(model.scanning || model.busy || model.snapshot?.vm.running != true)
          .accessibilityIdentifier("menu.sweep")
        Button {
          openSettings()
          NSApp.activate(ignoringOtherApps: true)
        } label: {
          Image(systemName: "gearshape")
        }.help("Settings").keyboardShortcut(",").accessibilityIdentifier("menu.settings")
      }
      HStack {
        Text("Context: colima").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
          .accessibilityIdentifier("menu.quit")
      }
    }.padding(16).frame(width: 340)
      .task { await model.refresh() }
  }

  private var header: some View {
    HStack(spacing: 10) {
      if let icon = NSApp.applicationIconImage {
        Image(nsImage: icon).resizable().frame(width: 40, height: 40)
      }
      VStack(alignment: .leading, spacing: 3) {
        Text("Colima Mini").font(.headline)
        HStack(spacing: 5) {
          Circle().fill(model.snapshot?.vm.running == true ? Color.green : Color.secondary)
            .frame(width: 6, height: 6)
          Text(model.snapshot?.vm.status ?? "Connecting…")
          if let snapshot = model.snapshot, snapshot.vm.running {
            Text(
              "· \(snapshot.containers.filter(\.running).count) of \(snapshot.containers.count) running"
            )
          }
          if model.sample { Text("Sample").foregroundStyle(.orange) }
        }.font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if model.snapshot?.vm.running == false {
        Button("Start") { model.request("start", containers: [], vm: true) }
          .disabled(model.busy || model.sample)
      }
      Button {
        Task { await model.refresh() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }.help("Refresh").accessibilityIdentifier("menu.refresh")
        .disabled(model.refreshing || model.busy)
    }
  }

  private func usage(_ snapshot: Snapshot) -> some View {
    let cpu = snapshot.totalCPU(snapshot.containers) / Double(max(1, snapshot.vm.cpus))
    let memory = snapshot.totalMemory(snapshot.containers)
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(String(format: "CPU %.1f%%", cpu))
        Spacer()
        Text("Memory " + memoryText(memory) + " / " + memoryText(Double(snapshot.vm.memory)))
      }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
      ProgressView(value: min(1, memory / Double(max(1, snapshot.vm.memory)))).tint(.blue)
        .controlSize(.small)
    }.help("Container totals relative to the VM allocation (\(snapshot.vm.allocation)).")
  }

  private var attention: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
      ForEach(model.attention) { container in
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text(container.service).lineLimit(1)
            Text(container.project + " · " + container.condition.title).font(.caption2)
              .foregroundStyle(.secondary).lineLimit(1)
          }
          Spacer()
          Button("Logs") { show(container, tab: .logs) }
          Button("Restart") {
            show(container)
            model.request("restart", containers: [container])
          }.disabled(model.busy || model.sample)
        }.controlSize(.small)
      }
    }
  }

  private func project(_ project: String) -> some View {
    let containers = model.containers.filter { $0.project == project }
    let origin = containers.lazy.compactMap(\.origin).first
    let isExpanded = expanded.contains(project)
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Button {
          if isExpanded { expanded.remove(project) } else { expanded.insert(project) }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
              .rotationEffect(.degrees(isExpanded ? 90 : 0)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
              Text(project).lineLimit(1).truncationMode(.middle)
              if let origin {
                Text(origin.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
              }
            }
            Spacer()
            if containers.contains(where: \.needsAttention) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text("\(containers.filter(\.running).count)/\(containers.count)")
              .foregroundStyle(.secondary).monospacedDigit()
          }.contentShape(Rectangle())
        }.buttonStyle(.plain).help(origin?.displayPath ?? "running/total containers")
        Menu {
          Button("Open in dashboard") { show(project: project) }
          ProjectActions.items(model: model, containers: containers)
          if let origin {
            Divider()
            OriginMenuItems(model: model, origin: origin)
          }
        } label: {
          Image(systemName: "ellipsis")
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
          .disabled(model.busy)
      }
      if isExpanded {
        ForEach(containers) { container in
          HStack(spacing: 6) {
            Circle().fill(container.condition.color).frame(width: 6, height: 6)
            Button(container.service) { show(container) }.buttonStyle(.plain).lineLimit(1)
              .help(container.name + " · " + container.status)
            Spacer()
            PortChips(ports: container.publishedPorts, limit: 2)
            if container.running {
              Button {
                Launcher.shell(container, model: model)
              } label: {
                Image(systemName: "terminal")
              }.buttonStyle(.borderless).help("Open shell").disabled(model.sample)
            }
          }.font(.callout).padding(.leading, 22)
        }
      }
    }.padding(.horizontal, 8).padding(.vertical, 6)
      .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
  }
}
