import AppKit
import ColimaAppState
import ColimaCore
import SwiftUI

struct DashboardView: View {
  @ObservedObject var model: Dashboard
  @State private var palette = false
  var body: some View {
    NavigationSplitView {
      SidebarView(model: model)
    } detail: {
      VStack(spacing: 0) {
        if model.sample {
          HStack {
            Label("Sample data · runtime changes disabled", systemImage: "testtube.2")
            Spacer()
          }.font(.caption).foregroundStyle(.orange).padding(.horizontal, 20).padding(.vertical, 8)
            .background(Color.orange.opacity(0.08))
        }
        if let error = model.error {
          StatusMessage(text: error)
        }
        page.frame(maxWidth: .infinity, maxHeight: .infinity)
        HStack(spacing: 8) {
          if model.refreshing || model.busy { ProgressView().controlSize(.small) }
          Text(model.busy ? "Applying action…" : "Context: colima")
          Spacer()
          Button {
            palette = true
          } label: {
            Label("Search", systemImage: "magnifyingglass")
          }
          .buttonStyle(.plain).keyboardShortcut("k", modifiers: .command)
          .accessibilityIdentifier("dashboard.search")
          Text("⌘K").foregroundStyle(.tertiary)
          if let date = model.lastRefresh {
            Text("Updated \(date.formatted(date: .omitted, time: .standard))")
          }
        }.font(.caption).foregroundStyle(.secondary).padding(10)
      }
    }
    .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 300)
    .onChange(of: model.grouped) { _, _ in model.savePreferences() }
    .onChange(of: model.onlyRunning) { _, _ in model.savePreferences() }
    .sheet(isPresented: $palette) { CommandPalette(model: model, presented: $palette) }
    .confirmationDialog(
      model.pending?.title ?? "Confirm action",
      isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }),
      titleVisibility: .visible
    ) {
      if let action = model.pending {
        Button(action.verb.capitalized, role: action.verb == "start" ? nil : .destructive) {
          Task { await model.perform(action) }
        }
      }
    } message: {
      Text(model.pending?.message ?? "")
    }
    .sheet(isPresented: $model.showingSweep) { CleanupReportView(model: model) }
    .sheet(isPresented: $model.showingReclaim) { ReclaimView(model: model) }
    .task { await model.refresh() }
    .hidingWindowTitle()
  }
  @ViewBuilder var page: some View {
    switch model.route {
    case .overview: OverviewView(model: model)
    case .containers: ContainersView(model: model)
    case .container(let id): ContainerDetailView(model: model, id: id).id(id)
    case .volumes: VolumesView(model: model)
    case .volume(let name): VolumeDetailView(model: model, name: name)
    case .images: ImagesView(model: model)
    case .image(let id): ImageDetailView(model: model, id: id)
    case .storage: StorageView(model: model)
    case .settings:
      ScrollView { SettingsView(model: model).frame(maxWidth: .infinity, alignment: .leading) }
    }
  }
}

struct ContainersView: View {
  @ObservedObject var model: Dashboard
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text(model.project == "All containers" ? "Containers" : model.project)
            .font(.system(.title, design: .rounded).weight(.semibold))
          Text(
            countText(model.visible.count, "container")
              + " · \(model.visible.filter(\.running).count) running"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if model.project != "All containers" {
          ProjectActions(model: model, containers: model.visible)
        }
        RefreshButton(busy: model.refreshing || model.busy) { await model.refresh() }
      }.padding(20)
      if let snapshot = model.snapshot {
        ResourceOverview(snapshot: snapshot).padding(.horizontal, 20).padding(.bottom, 16)
      }
      HStack(spacing: 12) {
        Picker("View", selection: $model.grouped) {
          Text("Projects").tag(true)
          Text("Containers").tag(false)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 175)
          .accessibilityIdentifier("dashboard.view")
        if model.grouped {
          Button {
            model.toggleVisibleGroups()
          } label: {
            Label(
              model.allVisibleGroupsCollapsed ? "Expand all" : "Collapse all",
              systemImage: model.allVisibleGroupsCollapsed
                ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
          }.fixedSize().disabled(!model.search.isEmpty || model.visible.isEmpty)
            .help(
              model.search.isEmpty
                ? "Toggle visible projects" : "Clear the search to collapse projects"
            )
            .accessibilityIdentifier("groups.toggle")
        }
        TextField("Filter containers or projects", text: $model.search).textFieldStyle(
          .roundedBorder)
        Toggle("Running only", isOn: $model.onlyRunning).toggleStyle(.checkbox)
      }.padding(.horizontal, 20).padding(.bottom, 12)
      if !model.search.isEmpty && model.grouped {
        Text("Matching projects are expanded while searching.")
          .font(.caption).foregroundStyle(.secondary).frame(
            maxWidth: .infinity, alignment: .leading
          )
          .padding(.horizontal, 20).padding(.bottom, 8)
      }
      ContainerList(model: model)
    }
  }
}

extension View {
  // The sidebar already names the app; the toolbar title only repeats it.
  @ViewBuilder func hidingWindowTitle() -> some View {
    if #available(macOS 15.0, *) {
      toolbar(removing: .title)
    } else {
      self
    }
  }
}
