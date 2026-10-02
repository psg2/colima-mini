import AppKit
import Charts
import ColimaAppState
import ColimaCore
import SwiftUI

private enum ContainerTab: String, CaseIterable {
  case overview = "Overview"
  case logs = "Logs"
  case ports = "Ports"
  case mounts = "Mounts"
}
struct ContainerDetailView: View {
  @ObservedObject var model: Dashboard
  let id: String
  @State private var tab = ContainerTab.overview
  @State private var logSearch = ""
  @State private var follow = true
  @State private var timestamps = true
  @Environment(\.scenePhase) private var scenePhase
  var currentDetails: ContainerDetails? { model.details?.id == id ? model.details : nil }
  var container: Container? { model.containers.first { $0.id == id } }
  var filteredLogs: String {
    model.logs.components(separatedBy: .newlines).filter {
      logSearch.isEmpty || $0.localizedCaseInsensitiveContains(logSearch)
    }.map { line in
      guard !timestamps, let space = line.firstIndex(of: " "), line.prefix(4).allSatisfy(\.isNumber)
      else { return line }
      return String(line[line.index(after: space)...])
    }.joined(separator: "\n")
  }
  var polling: Bool { tab == .logs && !model.logsPaused && scenePhase == .active }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        model.goBack()
      } label: {
        Label("Back", systemImage: "chevron.left")
      }
      .buttonStyle(.plain).foregroundStyle(.secondary).padding(.bottom, 18)
      .keyboardShortcut("[", modifiers: .command).accessibilityIdentifier("container.back")
      if let container {
        header(container)
        Picker("Container details", selection: $tab) {
          ForEach(ContainerTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 410).padding(.vertical, 18)
          .accessibilityIdentifier("container.tabs")
        if let error = model.detailsError { StatusMessage(text: error).padding(.bottom, 12) }
        if model.detailsLoading { ProgressView().controlSize(.small) }
        switch tab {
        case .overview: overview(container)
        case .logs: logsView
        case .ports: portsView
        case .mounts: mountsView
        }
      } else if model.snapshot == nil {
        ProgressView("Loading container…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.snapshot?.vm.running == false {
        EmptyPage(
          title: "Colima is stopped",
          message: "Start Colima from the sidebar to inspect this container.", symbol: "shippingbox"
        )
      } else {
        EmptyPage(
          title: "Container no longer exists",
          message: "Return to the list to select another container.", symbol: "shippingbox")
      }
    }.padding(24)
      .task(id: "\(id):\(tab.rawValue):\(scenePhase == .active)") {
        guard scenePhase == .active else { return }
        repeat {
          await model.loadDetails(id)
          guard tab == .overview else { return }
          do { try await Task.sleep(for: .seconds(30)) } catch { return }
        } while !Task.isCancelled
      }
      .task(id: polling) {
        guard polling else { return }
        while !Task.isCancelled {
          await model.loadLogs(id)
          do { try await Task.sleep(for: .seconds(model.refreshInterval)) } catch { return }
        }
      }
      .onChange(of: logSearch) { _, search in if !search.isEmpty { follow = false } }
  }
  private func header(_ c: Container) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text(c.service).font(.system(.title, design: .rounded).weight(.semibold))
          Text(c.name + " · " + c.image).font(.caption).foregroundStyle(.secondary).textSelection(
            .enabled)
        }
        Spacer()
        Button {
          Task {
            await model.refresh()
            await model.loadDetails(id)
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help("Refresh container details").disabled(model.busy || model.detailsLoading)
        .accessibilityIdentifier("container.refresh")
        if let folder = c.folder, !model.sample {
          Button {
            NSWorkspace.shared.open(folder)
          } label: {
            Label("Folder", systemImage: "folder")
          }
        }
        Button(c.running ? "Stop…" : "Start…") {
          model.request(c.running ? "stop" : "start", containers: [c])
        }
        .disabled(model.busy || model.sample).accessibilityIdentifier("container.toggle")
        Button("Restart…") { model.request("restart", containers: [c]) }
          .disabled(!c.running || model.busy || model.sample).accessibilityIdentifier(
            "container.restart")
      }
      HStack(spacing: 24) {
        Label(
          c.status, systemImage: c.needsAttention ? "exclamationmark.triangle.fill" : "circle.fill"
        )
        .foregroundStyle(c.needsAttention ? .orange : c.running ? .teal : .secondary)
        if let metric = model.snapshot?.metric(for: c) {
          Text("CPU " + metric.cpuPercent).monospacedDigit()
          Text("Memory " + memoryText(metric.memoryBytes)).monospacedDigit()
        }
      }.font(.caption)
      Divider()
    }
  }
  private func overview(_ c: Container) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 12) {
          relationship("Project", c.project)
          Image(systemName: "chevron.right").foregroundStyle(.tertiary)
          relationship("Service", c.service)
          if let mount = currentDetails?.mounts.first(where: { $0.type == "volume" }),
            let name = mount.name
          {
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            Button {
              model.openVolume(name)
            } label: {
              relationship("Persistent data", name)
            }
            .buttonStyle(.plain).foregroundStyle(.teal).accessibilityIdentifier(
              "container.volume." + name)
          }
          Spacer()
        }.padding(14).background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        if let details = currentDetails {
          Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 14) {
            fact("Image", details.image)
            fact("Health", details.state.health ?? "No health check")
            fact("Exit code", details.state.exitCode.map(String.init) ?? "Unavailable")
            fact("OOM killed", details.state.oomKilled.map { $0 ? "Yes" : "No" } ?? "Unavailable")
            fact("Restart count", details.restartCount.map(String.init) ?? "Unavailable")
            fact("Started", details.state.startedAt ?? "Unavailable")
            if let error = details.state.error, !error.isEmpty { fact("Runtime error", error) }
          }.textSelection(.enabled)
        }
        if let date = model.detailsDate {
          Text("Inspection fetched " + date.formatted(date: .omitted, time: .standard)).font(
            .caption
          ).foregroundStyle(.secondary)
        }
        metricHistory
        Spacer(minLength: 0)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private var metricHistory: some View {
    let samples = model.history[id] ?? []
    return VStack(alignment: .leading, spacing: 12) {
      Text("Recent resource usage").font(.headline)
      Text(
        "Up to 60 samples collected while this dashboard is open. CPU follows Docker's 100% per core convention."
      )
      .font(.caption).foregroundStyle(.secondary)
      if samples.count > 1 {
        HStack(spacing: 24) {
          VStack(alignment: .leading) {
            Text("CPU (%)").font(.caption).foregroundStyle(.secondary)
            Chart(samples) { sample in
              LineMark(x: .value("Time", sample.date), y: .value("CPU", sample.cpu))
                .foregroundStyle(.teal)
            }.frame(height: 135).chartYAxis { AxisMarks(position: .leading) }
          }
          VStack(alignment: .leading) {
            Text("Memory (MiB)").font(.caption).foregroundStyle(.secondary)
            Chart(samples) { sample in
              LineMark(
                x: .value("Time", sample.date), y: .value("Memory", sample.memory / 1_048_576)
              ).foregroundStyle(.teal)
            }.frame(height: 135).chartYAxis { AxisMarks(position: .leading) }
          }
        }
      } else {
        Text("Collecting samples…").font(.callout).foregroundStyle(.secondary)
      }
    }
  }
  private var logsView: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        TextField("Find in logs", text: $logSearch).textFieldStyle(.roundedBorder)
        Button(model.logsPaused ? "Resume" : "Pause") { model.logsPaused.toggle() }
          .accessibilityIdentifier("logs.pause")
        Toggle(
          "Follow latest", isOn: Binding(get: { follow && logSearch.isEmpty }, set: { follow = $0 })
        ).toggleStyle(.checkbox).disabled(!logSearch.isEmpty).help(
          "Searching pauses automatic following.")
        Toggle("Timestamps", isOn: $timestamps).toggleStyle(.checkbox)
        Button("Copy visible logs") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(filteredLogs, forType: .string)
        }
      }
      HStack {
        Text(
          model.logsPaused
            ? "Paused"
            : scenePhase != .active
              ? "Paused while inactive" : "Refreshes every \(model.refreshInterval)s")
        Text("· Last 200 lines")
        if model.logsLoading { ProgressView().controlSize(.small) }
        Spacer()
        if let date = model.logsDate {
          Text("Fetched " + date.formatted(date: .omitted, time: .standard))
        }
      }.font(.caption).foregroundStyle(.secondary)
      if let error = model.logError { StatusMessage(text: "Logs could not refresh. " + error) }
      LogConsole(text: filteredLogs, follow: follow && logSearch.isEmpty)
        .overlay {
          if model.logs.isEmpty && !model.logsLoading {
            Text(
              model.logError == nil
                ? "This container has not written any logs." : "No log buffer available."
            )
            .foregroundStyle(.secondary)
          } else if filteredLogs.isEmpty && !logSearch.isEmpty {
            Text("No matching log lines.").foregroundStyle(.secondary)
          }
        }
    }
  }
  private var portsView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        if let details = currentDetails {
          if details.ports.isEmpty { Text("No published ports.").foregroundStyle(.secondary) }
          ForEach(details.ports.indices, id: \.self) { index in
            let port = details.ports[index]
            HStack {
              VStack(alignment: .leading, spacing: 5) {
                Text(port.address).font(.system(.body, design: .monospaced))
                Text("Host → container \(port.containerPort) / \(port.protocolName.uppercased())")
                  .font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Button("Copy address") { copy(port.address) }
              if port.protocolName == "tcp" {
                Menu("Open as…") {
                  Button("HTTP") { open(port, scheme: "http") }
                  Button("HTTPS") { open(port, scheme: "https") }
                }.help("Choose a web protocol only if this port serves HTTP or HTTPS.")
              }
            }.padding(12).background(
              Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
          }
          Text(
            "TCP ports may serve a database or another protocol. Choose HTTP or HTTPS explicitly when opening a web service."
          )
          .font(.caption).foregroundStyle(.secondary)
        } else if !model.detailsLoading {
          Text("Port details are unavailable.").foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private var mountsView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        if let details = currentDetails {
          if details.mountsAvailable == false {
            Text("Mount metadata is unavailable.").foregroundStyle(.secondary)
          } else if details.mounts.isEmpty {
            Text("No mounts.").foregroundStyle(.secondary)
          }
          ForEach(details.mounts.indices, id: \.self) { index in
            let mount = details.mounts[index]
            HStack {
              Image(systemName: mount.type == "volume" ? "externaldrive" : "folder")
              VStack(alignment: .leading, spacing: 5) {
                if mount.type == "volume", let name = mount.name {
                  Button(name) { model.openVolume(name) }.buttonStyle(.link)
                } else {
                  Text(mount.source)
                }
                Text("\(mount.type) → \(mount.destination)").font(
                  .system(.caption, design: .monospaced)
                ).foregroundStyle(.secondary)
              }
              Spacer()
              Text(mount.readOnly ? "Read only" : "Read / write").font(.caption).foregroundStyle(
                .secondary)
            }.padding(12).background(
              Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
          }
          Text("Named volumes live inside Colima. Linux mount paths are not folders on your Mac.")
            .font(.caption).foregroundStyle(.secondary)
        } else if !model.detailsLoading {
          Text("Mount details are unavailable.").foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private func relationship(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
    }
  }
  private func fact(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value)
    }
  }
  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }
  private func open(_ port: PortBinding, scheme: String) {
    var components = URLComponents()
    components.scheme = scheme
    components.host =
      ["0.0.0.0", "::", ""].contains(port.hostAddress) ? "localhost" : port.hostAddress
    components.port = Int(port.hostPort)
    if let url = components.url { NSWorkspace.shared.open(url) }
  }
}

struct LogConsole: View {
  let text: String
  let follow: Bool
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView([.horizontal, .vertical]) {
        VStack(alignment: .leading, spacing: 0) {
          Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: false).frame(
              maxWidth: .infinity, alignment: .leading)
          Color.clear.frame(height: 1).id("tail")
        }.padding(12)
      }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .onChange(of: text) { _, _ in if follow { proxy.scrollTo("tail", anchor: .bottom) } }
        .onChange(of: follow) { _, value in if value { proxy.scrollTo("tail", anchor: .bottom) } }
        .accessibilityLabel("Container logs")
    }
  }
}
