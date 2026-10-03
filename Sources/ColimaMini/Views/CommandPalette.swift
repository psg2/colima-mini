import ColimaAppState
import SwiftUI

private struct PaletteResult: Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let symbol: String
  var route: AppRoute? = nil
  var project: String? = nil
  var run: (() -> Void)? = nil
}
struct CommandPalette: View {
  @ObservedObject var model: Dashboard
  @Binding var presented: Bool
  @State private var query = ""
  @State private var selected: String?
  @FocusState private var focused: Bool
  private var results: [PaletteResult] {
    var values = [
      ("Overview", AppRoute.overview), ("Containers", .containers), ("Images", .images),
      ("Volumes", .volumes), ("Networks", .networks),
      ("Storage", .storage), ("Settings", .settings),
    ].map {
      PaletteResult(
        id: "page." + $0.0, title: $0.0, subtitle: "Page", symbol: "arrow.turn.down.right",
        route: $0.1)
    }
    values += (model.snapshot?.projects ?? []).map {
      PaletteResult(
        id: "project." + $0, title: $0, subtitle: "Project", symbol: "folder", route: .containers,
        project: $0)
    }
    values += model.containers.map {
      PaletteResult(
        id: "container." + $0.id, title: $0.name, subtitle: $0.project + " · " + $0.status,
        symbol: "shippingbox", route: .container($0.id))
    }
    values += model.volumes.map {
      PaletteResult(
        id: "volume." + $0.name, title: $0.name, subtitle: "Volume", symbol: "externaldrive",
        route: .volume($0.name))
    }
    values += model.images.map {
      PaletteResult(
        id: "image." + $0.id, title: $0.name, subtitle: "Image", symbol: "square.3.layers.3d",
        route: .image($0.id))
    }
    // Actions appear once the user types, so the empty palette stays a navigator.
    if !query.isEmpty {
      if !model.sample {
        values.append(
          PaletteResult(
            id: "action.reclaim", title: "Reclaim space…", subtitle: "Action · preview first",
            symbol: "sparkles", run: { model.openReclaim() }))
        values.append(
          PaletteResult(
            id: "action.sweep", title: "Review unused containers…",
            subtitle: "Action · stale and orphaned stacks", symbol: "shippingbox",
            run: {
              model.navigate(.containers, project: "All containers")
              Task { await model.scan() }
            }))
      }
      values += (model.snapshot?.projects ?? []).filter { project in
        model.containers.contains { $0.project == project && $0.running }
      }.map { project in
        PaletteResult(
          id: "projectLogs." + project, title: "Show logs: " + project,
          subtitle: "Project action", symbol: "text.alignleft",
          run: { model.openProjectLogs(project) })
      }
      values += actions
    }
    return values.filter {
      query.isEmpty || ($0.title + " " + $0.subtitle).localizedCaseInsensitiveContains(query)
    }
  }
  private var actions: [PaletteResult] {
    model.containers.flatMap { container -> [PaletteResult] in
      var items = [
        PaletteResult(
          id: "logs." + container.id, title: "Show logs: " + container.name,
          subtitle: "Action", symbol: "text.alignleft",
          run: { model.openContainer(container.id, tab: .logs) })
      ]
      guard !model.sample else { return items }
      if container.running {
        items += [
          PaletteResult(
            id: "shell." + container.id, title: "Open shell: " + container.name,
            subtitle: "Action", symbol: "terminal",
            run: { Launcher.shell(container, model: model) }),
          PaletteResult(
            id: "restart." + container.id, title: "Restart: " + container.name,
            subtitle: "Action · asks first", symbol: "arrow.clockwise",
            run: { model.request("restart", containers: [container]) }),
          PaletteResult(
            id: "stop." + container.id, title: "Stop: " + container.name,
            subtitle: "Action · asks first", symbol: "stop",
            run: { model.request("stop", containers: [container]) }),
        ]
      } else {
        items.append(
          PaletteResult(
            id: "start." + container.id, title: "Start: " + container.name,
            subtitle: "Action · asks first", symbol: "play",
            run: { model.request("start", containers: [container]) }))
      }
      items += container.publishedPorts.map { port in
        PaletteResult(
          id: "port." + container.id + port.id, title: "Copy \(port.address): " + container.name,
          subtitle: "Port \(port.label)", symbol: "network",
          run: { Launcher.copy(port.address) })
      }
      return items
    }
  }
  private func choose(_ result: PaletteResult) {
    if let run = result.run {
      presented = false
      // Let the palette sheet dismiss before an action presents its own sheet or dialog.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { run() }
      return
    }
    guard let route = result.route else { return }
    switch route {
    case .container(let id): model.openContainer(id)
    case .volume(let name): model.openVolume(name)
    case .image(let id): model.openImage(id)
    default:
      model.navigate(
        route, project: route == .containers ? result.project ?? "All containers" : nil)
    }
    presented = false
  }
  private func move(_ offset: Int) {
    guard !results.isEmpty else { return }
    let current = results.firstIndex { $0.id == selected } ?? 0
    selected = results[(current + offset + results.count) % results.count].id
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search or type an action, such as restart or shell", text: $query)
          .textFieldStyle(.plain).focused($focused).accessibilityIdentifier("palette.search")
          .onSubmit {
            if let result = results.first(where: { $0.id == selected }) ?? results.first {
              choose(result)
            }
          }
        Button("Done") { presented = false }.keyboardShortcut(.cancelAction)
      }.padding(10)
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(results) { result in
              Button {
                choose(result)
              } label: {
                HStack(spacing: 10) {
                  Image(systemName: result.symbol).frame(width: 20).foregroundStyle(.secondary)
                  Text(result.title).lineLimit(1).truncationMode(.middle)
                  Spacer()
                  Text(result.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.padding(9).contentShape(Rectangle())
                  .background(
                    selected == result.id ? Color.accentColor.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5))
              }.buttonStyle(.plain).id(result.id)
            }
            if results.isEmpty {
              Text("No matching objects.").foregroundStyle(.secondary).padding(12)
            }
          }
        }.onChange(of: selected) { _, id in if let id { proxy.scrollTo(id) } }
      }
      Text(
        "↑↓ to choose · Return to open · Escape to close. Results use the latest loaded inventories."
      )
      .font(.caption).foregroundStyle(.secondary)
    }.padding(16).frame(width: 600, height: 420)
      .onAppear {
        focused = true
        selected = results.first?.id
      }
      .onChange(of: query) { _, _ in selected = results.first?.id }
      .onKeyPress(.downArrow) {
        move(1)
        return .handled
      }
      .onKeyPress(.upArrow) {
        move(-1)
        return .handled
      }
  }
}
