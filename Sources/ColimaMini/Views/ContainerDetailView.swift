import AppKit
import Charts
import ColimaAppState
import ColimaCore
import SwiftUI

struct ContainerDetailView: View {
  @ObservedObject var model: Dashboard
  let id: String
  @Environment(\.scenePhase) private var scenePhase
  var currentDetails: ContainerDetails? { model.details?.id == id ? model.details : nil }
  var container: Container? { model.containers.first { $0.id == id } }
  var tab: ContainerPageTab { model.containerTab }
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
        Picker("Container details", selection: $model.containerTab) {
          ForEach(ContainerPageTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
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
      // Restarting the container ends Docker's stream; following resumes once
      // it runs again.
      .task(id: "\(polling):\(container?.running == true)") {
        guard polling else { return }
        await model.followLogs(id)
      }
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
        if c.running {
          Button {
            Launcher.shell(c, model: model)
          } label: {
            Label("Shell", systemImage: "terminal")
          }.disabled(model.sample).help("Open an interactive shell in Terminal")
            .accessibilityIdentifier("container.shell")
        }
        if let origin = c.origin {
          Menu {
            OriginMenuItems(model: model, origin: origin)
          } label: {
            Label("Project folder", systemImage: "folder")
          }.fixedSize().help(origin.displayPath)
        }
        Button(c.running ? "Stop…" : "Start…") {
          model.request(c.running ? "stop" : "start", containers: [c])
        }
        .disabled(model.busy || model.sample).accessibilityIdentifier("container.toggle")
        if !c.running {
          Button("Remove…") { model.request("rm", containers: [c]) }
            .disabled(model.busy || model.sample).accessibilityIdentifier("container.remove")
        }
        Button("Restart…") { model.request("restart", containers: [c]) }
          .disabled(!c.running || model.busy || model.sample).accessibilityIdentifier(
            "container.restart")
      }
      HStack(spacing: 16) {
        ConditionPill(condition: c.condition)
        Text(c.uptime).foregroundStyle(.secondary)
        if !c.publishedPorts.isEmpty { PortChips(ports: c.publishedPorts, limit: 6) }
        if let metric = model.snapshot?.metric(for: c) {
          Text("CPU " + metric.cpuPercent).monospacedDigit()
          Text("Memory " + memoryText(metric.memoryBytes)).monospacedDigit()
          if let network = metric.networkIO {
            Text("Net I/O " + network).monospacedDigit().help("Received / sent since start")
          }
          if let block = metric.blockIO {
            Text("Disk I/O " + block).monospacedDigit().help("Read / written since start")
          }
          if let pids = metric.pids { Text("PIDs " + pids).monospacedDigit() }
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
    LogPanel(
      model: model, running: container?.running,
      emptyMessage: "This container has not written any logs.")
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
