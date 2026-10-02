import ColimaAppState
import SwiftUI

private struct PaletteResult: Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let symbol: String
  let route: AppRoute
  var project: String? = nil
}
struct CommandPalette: View {
  @ObservedObject var model: Dashboard
  @Binding var presented: Bool
  @State private var query = ""
  @State private var selected: String?
  @FocusState private var focused: Bool
  private var results: [PaletteResult] {
    var values = [
      ("Containers", AppRoute.containers), ("Volumes", .volumes), ("Images", .images),
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
    return values.filter {
      query.isEmpty || ($0.title + " " + $0.subtitle).localizedCaseInsensitiveContains(query)
    }
  }
  private func choose(_ result: PaletteResult) {
    switch result.route {
    case .container(let id): model.openContainer(id)
    case .volume(let name): model.openVolume(name)
    case .image(let id): model.openImage(id)
    default:
      model.navigate(
        result.route,
        project: result.route == .containers ? result.project ?? "All containers" : nil)
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
        TextField("Search containers, projects, volumes or images", text: $query)
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
