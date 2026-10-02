import AppKit
import ColimaAppState
import SwiftUI

// Search, pause, follow and copy controls over the model's followed log buffer.
// With services, lines carry a "[service]" label that can be filtered.
struct LogPanel: View {
  @ObservedObject var model: Dashboard
  let running: Bool?
  let emptyMessage: String
  var services: [String] = []
  @State private var search = ""
  @State private var follow = true
  @State private var timestamps = true
  @State private var hidden: Set<String> = []
  @AppStorage("logWrap") private var wrap = false
  @Environment(\.scenePhase) private var scenePhase
  var visible: String {
    model.logs.components(separatedBy: .newlines).filter { line in
      (search.isEmpty || line.localizedCaseInsensitiveContains(search))
        && (hidden.isEmpty || !hidden.contains { line.contains("[\($0)] ") })
    }.map { line in
      guard !timestamps, let space = line.firstIndex(of: " "), line.prefix(4).allSatisfy(\.isNumber)
      else { return line }
      return String(line[line.index(after: space)...])
    }.joined(separator: "\n")
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        TextField("Find in logs", text: $search).textFieldStyle(.roundedBorder)
        if !services.isEmpty {
          Menu("Services") {
            ForEach(services, id: \.self) { service in
              Toggle(
                service,
                isOn: Binding(
                  get: { !hidden.contains(service) },
                  set: { if $0 { hidden.remove(service) } else { hidden.insert(service) } }))
            }
          }.fixedSize().help("Choose which services' lines to show")
        }
        Button(model.logsPaused ? "Resume" : "Pause") { model.logsPaused.toggle() }
          .accessibilityIdentifier("logs.pause")
        Toggle(
          "Follow latest", isOn: Binding(get: { follow && search.isEmpty }, set: { follow = $0 })
        ).toggleStyle(.checkbox).disabled(!search.isEmpty).help(
          "Searching pauses automatic following.")
        Toggle("Timestamps", isOn: $timestamps).toggleStyle(.checkbox)
        Toggle("Wrap lines", isOn: $wrap).toggleStyle(.checkbox)
          .accessibilityIdentifier("logs.wrap")
        Button("Copy visible logs") { Launcher.copy(visible) }
      }
      HStack {
        if model.logsLive && !model.logsPaused {
          Label("Live", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.green)
        } else {
          Text(
            model.logsPaused
              ? "Paused"
              : scenePhase != .active
                ? "Paused while inactive"
                : running == false ? "Not running" : "Connecting…")
        }
        Text("· Up to \(Dashboard.logLineLimit) lines, starting with the last 500")
        if model.logsLoading { ProgressView().controlSize(.small) }
        Spacer()
        if let date = model.logsDate {
          Text("Last output " + date.formatted(date: .omitted, time: .standard))
        }
      }.font(.caption).foregroundStyle(.secondary)
      if let error = model.logError { StatusMessage(text: "Logs stopped following. " + error) }
      LogConsole(text: visible, follow: follow && search.isEmpty, wrap: wrap)
        .overlay {
          if model.logs.isEmpty && !model.logsLoading {
            Text(model.logError == nil ? emptyMessage : "No log buffer available.")
              .foregroundStyle(.secondary)
          } else if visible.isEmpty && !model.logs.isEmpty {
            Text("No matching log lines.").foregroundStyle(.secondary)
          }
        }
    }
    .onChange(of: search) { _, value in if !value.isEmpty { follow = false } }
  }
}

struct ProjectLogsView: View {
  @ObservedObject var model: Dashboard
  let project: String
  @Environment(\.scenePhase) private var scenePhase
  private var running: [String] {
    model.containers.filter { $0.project == project && $0.running }.map(\.service).sorted()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Button {
        model.goBack()
      } label: {
        Label("Back", systemImage: "chevron.left")
      }
      .buttonStyle(.plain).foregroundStyle(.secondary)
      .keyboardShortcut("[", modifiers: .command).accessibilityIdentifier("projectLogs.back")
      VStack(alignment: .leading, spacing: 5) {
        Text(project).font(.system(.title, design: .rounded).weight(.semibold))
        Text(
          running.isEmpty
            ? "No running services" : "Logs from " + running.joined(separator: ", ")
        ).font(.caption).foregroundStyle(.secondary)
      }
      LogPanel(
        model: model, running: !running.isEmpty,
        emptyMessage: running.isEmpty
          ? "Start the project to follow its logs." : "No output yet.",
        services: running)
    }.padding(24)
      // A service starting or stopping changes the set of followed sources.
      .task(id: "\(model.logsPaused):\(scenePhase == .active):\(running)") {
        guard !model.logsPaused, scenePhase == .active else { return }
        await model.followProjectLogs(project)
      }
  }
}
