import Charts
import ColimaAppState
import ColimaCore
import SwiftUI

struct OverviewView: View {
    @ObservedObject var model: Dashboard
    @Environment(\.openSettings) private var openSettings
    private var category: (String) -> DockerStorageCategory? {
        { type in model.storage?.docker.first { $0.type == type } }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Overview").font(.system(.title, design: .rounded).weight(.semibold))
                        Text("The default Colima profile at a glance").font(.caption).foregroundStyle(
                            .secondary)
                    }
                    Spacer()
                    RefreshButton(busy: model.refreshing || model.storageLoading) {
                        await model.refresh()
                        await model.loadStorage()
                    }
                }
                vmCard
                if let snapshot = model.snapshot, snapshot.vm.running {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12
                    ) {
                        stat(
                            "\(snapshot.containers.filter(\.running).count)", "Running",
                            "of \(countText(snapshot.containers.count, "container"))", "shippingbox"
                        ) {
                            model.onlyRunning = true
                            model.navigate(.containers, project: "All containers")
                        }
                        stat(
                            "\(snapshot.projects.filter { $0 != "Standalone" }.count)", "Projects",
                            "Compose stacks", "square.stack.3d.up"
                        ) {
                            model.grouped = true
                            model.navigate(.containers, project: "All containers")
                        }
                        stat(
                            "\(model.attention.count)", "Need attention",
                            model.attention.isEmpty ? "All clear" : "Unhealthy or failed",
                            "exclamationmark.triangle", tint: model.attention.isEmpty ? .secondary : .orange
                        ) { model.navigate(.containers, project: "All containers") }
                        stat(
                            category("Images").flatMap(\.totalCount).map(String.init) ?? "—", "Images",
                            reclaimable(category("Images")), "square.3.layers.3d"
                        ) { model.navigate(.images) }
                        stat(
                            category("Local Volumes").flatMap(\.totalCount).map(String.init) ?? "—", "Volumes",
                            reclaimable(category("Local Volumes")), "externaldrive"
                        ) { model.navigate(.volumes) }
                    }
                    if !model.attention.isEmpty { attention }
                    HStack(alignment: .top, spacing: 12) {
                        usage(snapshot)
                        cpuHistory
                    }
                }
                if let error = model.storageError { StatusMessage(text: error) }
            }.padding(24).frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
        }.task { await model.loadStorage() }
    }

    private var vmCard: some View {
        HStack(spacing: 14) {
            Circle().fill(model.snapshot?.vm.running == true ? Color.green : Color.secondary)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    model.snapshot.map { $0.vm.running ? "Colima is running" : "Colima is stopped" }
                        ?? "Connecting…"
                ).font(.headline)
                Text(vmFacts).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let vm = model.snapshot?.vm {
                Button("Resources…") { SettingsOpener(openSettings: openSettings)(.resources) }
                    .help("CPU, memory and disk for the VM")
                Group {
                    if vm.running {
                        Button("Restart…") { model.request("restart", containers: [], vm: true) }
                        Button("Stop…") { model.request("stop", containers: [], vm: true) }
                    } else {
                        Button("Start") { model.request("start", containers: [], vm: true) }
                            .buttonStyle(.borderedProminent)
                    }
                }.disabled(model.busy || model.sample)
            }
        }.padding(16).background(card)
    }
    private var vmFacts: String {
        guard let vm = model.snapshot?.vm else { return "Default profile" }
        var parts = ["Profile \(vm.name)"]
        if let runtime = vm.runtime { parts.append(runtime) }
        if let arch = vm.arch { parts.append(arch) }
        parts.append(vm.allocation)
        return parts.joined(separator: " · ")
    }
    private var attention: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Needs attention").font(.headline)
            ForEach(model.attention) { container in
                HStack(spacing: 10) {
                    ConditionPill(condition: container.condition)
                    Text(container.name).lineLimit(1).truncationMode(.middle)
                    Text(container.project).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Logs") { model.openContainer(container.id, tab: .logs) }
                    Button("Restart…") { model.request("restart", containers: [container]) }
                        .disabled(model.busy || model.sample)
                }
            }
        }.padding(16).background(card)
    }
    private func usage(_ snapshot: Snapshot) -> some View {
        let cpu = snapshot.totalCPU(snapshot.containers) / Double(max(1, snapshot.vm.cpus))
        let memory = snapshot.totalMemory(snapshot.containers)
        let filesystem = model.storage?.filesystem
        return VStack(alignment: .leading, spacing: 16) {
            Text("Resource usage").font(.headline)
            meter(
                "Container CPU", String(format: "%.1f%% of %d CPUs", cpu, snapshot.vm.cpus), cpu / 100,
                .teal)
            meter(
                "Container memory",
                memoryText(memory) + " / " + memoryText(Double(snapshot.vm.memory)),
                memory / Double(max(1, snapshot.vm.memory)), .blue)
            if let filesystem {
                meter(
                    "Docker data disk",
                    bytesText(Double(filesystem.usedBytes)) + " / " + bytesText(Double(filesystem.sizeBytes)),
                    Double(filesystem.usedBytes) / Double(filesystem.sizeBytes),
                    filesystem.isLow ? .orange : .purple)
            }
            HStack {
                Text("Totals exclude the VM operating system.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Storage details") { model.navigate(.storage) }.buttonStyle(.link).font(.caption)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(card)
    }
    private var cpuHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Container CPU").font(.headline)
                Spacer()
                if let last = model.totalHistory.last {
                    Text(String(format: "%.1f%% now", last.cpu)).font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if model.totalHistory.count > 1 {
                Chart(model.totalHistory) { sample in
                    AreaMark(x: .value("Time", sample.date), y: .value("CPU", sample.cpu))
                        .foregroundStyle(.teal.opacity(0.18))
                    LineMark(x: .value("Time", sample.date), y: .value("CPU", sample.cpu))
                        .foregroundStyle(.teal)
                }.chartYAxis { AxisMarks(position: .leading) }.frame(height: 130)
            } else {
                Text("Collecting samples while Colima Mini runs…").font(.callout)
                    .foregroundStyle(.secondary).frame(height: 130)
            }
            Text("Share of the VM's CPUs used by containers. Up to 60 samples.").font(.caption)
                .foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(card)
    }
    private func meter(_ title: String, _ value: String, _ fraction: Double, _ tint: Color)
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, max(0, fraction.isFinite ? fraction : 0))).tint(tint)
        }
    }
    private func stat(
        _ value: String, _ title: String, _ detail: String, _ symbol: String,
        tint: Color = .secondary, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(tint)
                    Spacer()
                }
                Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(card)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("overview.stat." + title)
    }
    private func reclaimable(_ category: DockerStorageCategory?) -> String {
        guard let bytes = category?.reclaimableBytes else {
            return model.storageLoading ? "Measuring…" : "Size unavailable"
        }
        return bytesText(bytes) + " reclaimable"
    }
    private var card: some View {
        RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor))
    }
}
