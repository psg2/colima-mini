import AppKit
import ColimaAppState
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct ContainerRow: View {
  @ObservedObject var model: Dashboard
  let container: Container
  let showProject: Bool
  @State private var hovering = false
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: container.needsAttention ? "exclamationmark.triangle" : "shippingbox")
        .foregroundStyle(container.needsAttention ? Color.orange : Color.secondary)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(container.service).fontWeight(.medium).lineLimit(1)
          if !container.publishedPorts.isEmpty { PortChips(ports: container.publishedPorts) }
        }
        Text(
          showProject
            ? container.project + " · " + container.image
            : container.name + " · " + container.image
        )
        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
      }.frame(maxWidth: .infinity, alignment: .leading)
      if hovering { quickActions }
      VStack(alignment: .leading, spacing: 3) {
        ConditionPill(condition: container.condition)
        if container.running {
          Text(container.uptime).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
      }.frame(width: 150, alignment: .leading)
      Text(model.snapshot?.metric(for: container)?.cpuPercent ?? "—")
        .frame(width: 65, alignment: .trailing).monospacedDigit()
      Text(model.snapshot?.metric(for: container).map { memoryText($0.memoryBytes) } ?? "—")
        .frame(width: 90, alignment: .trailing).monospacedDigit()
    }.padding(.horizontal, 12).padding(.vertical, 9)
      .contentShape(Rectangle())
      .background(
        model.selectedID == container.id
          ? Color.accentColor.opacity(0.18)
          : hovering ? Color.primary.opacity(0.04) : Color.clear
      )
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .onHover { hovering = $0 }
      .onTapGesture { model.openContainer(container.id) }
      .contextMenu { ContainerMenuItems(model: model, container: container) }
      .help(container.name + " · " + container.status)
      .accessibilityElement(children: .contain)
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { model.openContainer(container.id) }
      .accessibilityIdentifier("container.row." + container.name)
  }
  private var quickActions: some View {
    HStack(spacing: 2) {
      iconButton("Logs", "text.alignleft") { model.openContainer(container.id, tab: .logs) }
      if container.running {
        iconButton("Open shell", "terminal") { Launcher.shell(container, model: model) }
          .disabled(model.sample)
        iconButton("Restart…", "arrow.clockwise") {
          model.request("restart", containers: [container])
        }.disabled(model.busy || model.sample)
      } else {
        iconButton("Start…", "play") { model.request("start", containers: [container]) }
          .disabled(model.busy || model.sample)
      }
    }
  }
  private func iconButton(_ title: String, _ symbol: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol).frame(width: 22, height: 22).contentShape(Rectangle())
    }.buttonStyle(.borderless).help(title).accessibilityLabel(title)
  }
}

struct ContainerMenuItems: View {
  @ObservedObject var model: Dashboard
  let container: Container
  var body: some View {
    Button("Open") { model.openContainer(container.id) }
    Button("Show logs") { model.openContainer(container.id, tab: .logs) }
    Button("Open shell") { Launcher.shell(container, model: model) }
      .disabled(!container.running || model.sample)
    Divider()
    if container.running {
      Button("Restart…") { model.request("restart", containers: [container]) }
      Button("Stop…") { model.request("stop", containers: [container]) }
    } else {
      Button("Start…") { model.request("start", containers: [container]) }
    }
    Divider()
    Button("Copy name") { Launcher.copy(container.name) }
    ForEach(container.publishedPorts) { port in
      Button("Copy \(port.address)") { Launcher.copy(port.address) }
    }
  }
}
