import AppKit
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct DashboardView: View {
  @ObservedObject var model: Dashboard
  @Environment(\.openSettings) private var openSettings
  @State private var detail = "Logs"
  @State private var logSearch = ""
  var filteredLogs: String {
    let text = model.logError ?? model.logs
    guard !logSearch.isEmpty else { return text }
    return text.components(separatedBy: .newlines).filter {
      $0.localizedCaseInsensitiveContains(logSearch)
    }.joined(separator: "\n")
  }
  var body: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 8) {
          if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon).resizable().frame(width: 28, height: 28)
          }
          Text("Colima Mini").font(.title3.weight(.semibold))
        }
        HStack(spacing: 7) {
          Circle().fill(model.snapshot?.vm.running == true ? Color.green : Color.secondary).frame(
            width: 7, height: 7)
          Text(model.snapshot?.vm.status ?? "Connecting…").font(.subheadline)
          if model.sample { Text("Sample").font(.caption).foregroundStyle(.orange) }
        }
        Text(model.snapshot?.vm.allocation ?? "Default profile").font(.caption).foregroundStyle(
          .secondary)
        HStack {
          Button("Start") { model.request("start", containers: [], vm: true) }
            .accessibilityIdentifier("vm.start")
            .disabled(model.snapshot?.vm.running != false || model.busy || model.sample)
          Button("Stop") { model.request("stop", containers: [], vm: true) }
            .accessibilityIdentifier("vm.stop")
            .disabled(model.snapshot?.vm.running != true || model.busy || model.sample)
        }
      }.padding()
      List(selection: $model.project) {
        Label("All containers", systemImage: "square.stack.3d.up").tag("All containers")
        Section("Projects") {
          ForEach(model.snapshot?.projects ?? [], id: \.self) { project in
            HStack {
              Label(project, systemImage: project == "Standalone" ? "shippingbox" : "folder")
              Spacer()
              Text("\(model.containers.filter { $0.project == project }.count)").foregroundStyle(
                .secondary)
            }.tag(project)
          }
        }
      }.listStyle(.sidebar)
      Button {
        Task { await model.scan() }
      } label: {
        Label("Unused containers", systemImage: "sparkle.magnifyingglass")
      }
      .disabled(model.scanning || model.busy || model.snapshot?.vm.running != true).padding(
        .horizontal
      ).padding(.top, 8)
      Button {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
      } label: {
        Label("Settings", systemImage: "gearshape")
      }
      .accessibilityIdentifier("dashboard.settings").padding(.horizontal).padding(.bottom)
    } detail: {
      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(model.project).font(.title2.weight(.semibold))
            Text(
              "\(model.visible.count) \(model.visible.count == 1 ? "container" : "containers") · \(model.visible.filter(\.running).count) running"
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            Task { await model.refresh() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .help("Refresh").keyboardShortcut("r", modifiers: .command).disabled(
            model.refreshing || model.busy)
          if model.project != "All containers" {
            ProjectActions(model: model, containers: model.visible)
          }
        }.padding()
        if let snapshot = model.snapshot {
          ResourceOverview(snapshot: snapshot).padding(.horizontal).padding(.bottom, 12)
        }
        HStack(spacing: 12) {
          Picker("View", selection: $model.grouped) {
            Text("Projects").tag(true)
            Text("Containers").tag(false)
          }.pickerStyle(.segmented).labelsHidden().frame(width: 175).accessibilityIdentifier(
            "dashboard.view")
          if model.grouped {
            Menu("Groups") {
              Button("Expand all") {
                model.collapsed.removeAll()
                model.savePreferences()
              }
              Button("Collapse all") {
                model.collapsed.formUnion(model.visible.map(\.project))
                model.savePreferences()
              }.disabled(!model.search.isEmpty)
            }.fixedSize()
          }
          TextField("Filter containers or projects", text: $model.search).textFieldStyle(
            .roundedBorder)
          Toggle("Running only", isOn: $model.onlyRunning).toggleStyle(.checkbox)
        }.padding(.horizontal).padding(.bottom, 8)
        if let error = model.error {
          HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(error).textSelection(.enabled).font(.callout)
            Spacer()
          }.padding().background(Color.orange.opacity(0.09))
        }
        VSplitView {
          ContainerList(model: model).frame(minHeight: 150)
          containerDetail.frame(minHeight: 210)
        }
        HStack(spacing: 8) {
          if model.refreshing || model.busy { ProgressView().controlSize(.small) }
          Text(model.busy ? "Applying action…" : "Context: colima").font(.caption).foregroundStyle(
            .secondary)
          Spacer()
          if let date = model.lastRefresh {
            Text("Updated \(date.formatted(date: .omitted, time: .standard))").font(.caption)
              .foregroundStyle(.secondary)
          }
        }.padding(10)
      }
    }
    .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 300)
    .onChange(of: model.grouped) { _, _ in model.savePreferences() }
    .onChange(of: model.onlyRunning) { _, _ in model.savePreferences() }
    .confirmationDialog(
      model.pending?.title ?? "Confirm action",
      isPresented: Binding(
        get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }),
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
    .sheet(isPresented: $model.showingSweep) {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text("Unused containers").font(.title2)
          Spacer()
          if model.scanning { ProgressView() }
        }
        Text("Report only. Volumes and containers are kept.").font(.callout).foregroundStyle(
          .secondary)
        ConsoleText(text: model.sweepReport)
        HStack {
          Button("Scan again") { Task { await model.scan() } }.disabled(model.scanning)
          Spacer()
          Button("Done") { model.showingSweep = false }.keyboardShortcut(.defaultAction)
        }
      }.padding(24).frame(width: 780, height: 440)
    }
    .task {
      while !Task.isCancelled {
        await model.refresh()
        try? await Task.sleep(
          for: .seconds(NSApp.isActive ? model.refreshInterval : max(30, model.refreshInterval)))
      }
    }
    .task(id: model.selectedID) {
      model.logs = "Loading logs…"
      model.logError = nil
      logSearch = ""
      guard let id = model.selectedID else { return }
      while !Task.isCancelled {
        await model.loadLogs(id)
        try? await Task.sleep(for: .seconds(model.refreshInterval))
      }
    }
  }
  @ViewBuilder var containerDetail: some View {
    if let c = model.selected {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(c.name).font(.headline)
          Spacer()
          if let folder = c.folder {
            Button {
              NSWorkspace.shared.open(folder)
            } label: {
              Label("Folder", systemImage: "folder")
            }
          }
          Button(c.running ? "Stop" : "Start") {
            model.request(c.running ? "stop" : "start", containers: [c])
          }
          .accessibilityIdentifier("container.toggle")
          Button("Restart") { model.request("restart", containers: [c]) }.disabled(!c.running)
            .accessibilityIdentifier("container.restart")
        }.disabled(model.busy || model.sample)
        HStack {
          Picker("Details", selection: $detail) {
            Text("Logs").tag("Logs")
            Text("Ports").tag("Ports")
          }.pickerStyle(.segmented).frame(width: 160)
          Spacer()
          if detail == "Logs" {
            if model.logsLoading { ProgressView().controlSize(.small) }
            TextField("Find in logs", text: $logSearch).textFieldStyle(.roundedBorder).frame(
              width: 180)
            Button("Copy logs") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(filteredLogs, forType: .string)
            }
            Text("Last 200 lines · \(model.refreshInterval)s").font(.caption).foregroundStyle(
              .secondary)
          }
        }
        if detail == "Logs" {
          ConsoleText(
            text: filteredLogs.isEmpty && !logSearch.isEmpty
              ? "No matching log lines." : filteredLogs
          )
          .accessibilityLabel("Container logs")
        } else {
          VStack(alignment: .leading, spacing: 10) {
            Text(c.ports.isEmpty ? "No published ports." : c.ports).font(
              .system(.body, design: .monospaced)
            ).textSelection(.enabled)
            ForEach(c.endpoints, id: \.absoluteString) { url in
              HStack {
                Text("localhost:" + String(url.port ?? 80)).monospaced()
                Button("Copy address") {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                Button("Open in browser") { NSWorkspace.shared.open(url) }
              }
            }
            Spacer()
          }
        }
      }.padding(16)
    } else {
      VStack(spacing: 8) {
        Image(systemName: "shippingbox").font(.system(size: 28)).foregroundStyle(.secondary)
        Text(
          model.snapshot?.vm.running == false
            ? "Start Colima to view containers" : "Select a container")
        Text("Logs, ports and controls appear here.").font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
