import ColimaAppState
import ColimaCore
import SwiftUI

struct NetworksView: View {
  @ObservedObject var model: Dashboard
  @State private var unusedOnly = false
  @State private var expanded: Set<String> = []
  @State private var removing: DockerNetwork?
  private var visible: [DockerNetwork] {
    model.networks.filter { network in
      let text = ([network.name, network.project ?? "", network.driver] + network.subnets)
        .joined(separator: " ")
      return
        (model.networkSearch.isEmpty || text.localizedCaseInsensitiveContains(model.networkSearch))
        && (!unusedOnly || (network.members.isEmpty && !network.builtin))
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("Networks").font(.system(.title, design: .rounded).weight(.semibold))
          Text("Docker networks, their subnets and the running containers on them")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Remove unused…") { model.openReclaim(.networks) }
          .disabled(model.busy || model.sample || model.snapshot?.vm.running != true)
          .help("Preview networks no container uses, then remove the ones you choose")
        RefreshButton(busy: model.networksLoading) { await model.loadNetworks() }
      }
      HStack {
        TextField("Filter networks, projects or subnets", text: $model.networkSearch)
          .findable(model).textFieldStyle(.roundedBorder)
        Toggle("Unused only", isOn: $unusedOnly).toggleStyle(.checkbox)
      }
      Text(
        "Compose creates a network per project. Docker lists only running containers on a network, so stopped ones can still use an empty network; removal never forces."
      ).font(.caption).foregroundStyle(.secondary)
      if let error = model.networksError { StatusMessage(text: error) }
      if model.networksLoading && model.networks.isEmpty { ProgressView().controlSize(.small) }
      if visible.isEmpty && !model.networksLoading {
        EmptyPage(
          title: model.networksError == nil ? "No matching networks" : "Networks unavailable",
          message: "Adjust the filter or start Colima and refresh.",
          symbol: "point.3.connected.trianglepath.dotted")
      } else {
        ScrollView {
          LazyVStack(spacing: 1) {
            ForEach(visible) { network in
              row(network)
              Divider()
            }
          }
        }
      }
    }.padding(24).task { await model.loadNetworks() }
      .confirmationDialog(
        "Remove \(removing?.name ?? "network")?",
        isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
        titleVisibility: .visible
      ) {
        if let network = removing {
          Button("Remove", role: .destructive) { Task { await model.removeNetwork(network) } }
        }
      } message: {
        Text(
          "Docker refuses if a stopped container still uses it. Compose recreates project networks on the next Up."
        )
      }
  }

  private func row(_ network: DockerNetwork) -> some View {
    let open = expanded.contains(network.id)
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Button {
          if open { expanded.remove(network.id) } else { expanded.insert(network.id) }
        } label: {
          Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0))
            .frame(width: 14)
        }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(network.members.isEmpty)
        Image(systemName: network.builtin ? "lock" : "point.3.connected.trianglepath.dotted")
          .foregroundStyle(.secondary).frame(width: 18)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(network.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
            if network.builtin {
              Text("Built-in").font(.caption2).foregroundStyle(.secondary)
            }
            if network.internal {
              Text("Internal").font(.caption2).foregroundStyle(.orange)
            }
          }
          Text(
            [network.driver, network.subnets.joined(separator: ", ")].filter { !$0.isEmpty }
              .joined(separator: " · ")
          ).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
        Spacer()
        if let project = network.project {
          Button(project) { model.navigate(.containers, project: project) }
            .buttonStyle(.link).font(.caption).lineLimit(1)
            .help("Open the \(project) project")
        }
        Text(
          network.members.isEmpty
            ? "No running containers" : countText(network.members.count, "container")
        )
        .font(.caption).foregroundStyle(.secondary).frame(width: 140, alignment: .trailing)
        Button("Remove…") { removing = network }
          .controlSize(.small)
          .disabled(network.builtin || !network.members.isEmpty || model.busy || model.sample)
          .help(
            network.builtin
              ? "Docker's built-in networks can't be removed"
              : network.members.isEmpty ? "Remove this network" : "Containers are connected")
      }
      if open {
        ForEach(network.members) { member in
          HStack {
            if let container = model.containers.first(where: {
              $0.id.hasPrefix(member.id) || member.id.hasPrefix($0.id)
            }) {
              Button(member.name) { model.openContainer(container.id) }.buttonStyle(.link)
            } else {
              Text(member.name)
            }
            Spacer()
            Text(member.address ?? "").font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary).textSelection(.enabled)
          }.padding(.leading, 52).font(.callout)
        }
      }
    }.padding(.vertical, 10).padding(.horizontal, 8)
  }
}
