import ColimaAppState
import ColimaCore
import SwiftUI

// The scan suggests; the user picks groups and cleans them up in one step.
// Rows follow the live container list, so a removed group disappears.
struct UnusedContainersView: View {
    @ObservedObject var model: Dashboard
    @State private var showKept = false
    @State private var confirming = false
    private var groups: [SweepGroup] {
        (model.sweepGroups ?? []).filter { !model.members(of: $0).isEmpty }
    }
    private var suggested: [SweepGroup] { groups.filter(\.verdict.suggested) }
    private var kept: [SweepGroup] { groups.filter { !$0.verdict.suggested } }
    var body: some View {
        let plan = model.sweepPlan
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Unused containers").font(.title2.weight(.semibold))
                    Spacer()
                    if model.scanning { ProgressView().controlSize(.small) }
                    Button {
                        Task { await model.scan() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }.help("Scan again").disabled(model.scanning || model.busy)
                }
                Text(
                    "Each project is checked for clients on its published ports, network traffic and recent log lines. Pick what to clean up; volumes are always kept."
                ).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = model.sweepError { StatusMessage(text: error) }
            }.padding([.horizontal, .top], 24).padding(.bottom, 12)
            if model.sweepGroups == nil {
                Group {
                    if model.scanning { ProgressView("Checking clients, traffic and logs…") } else { Spacer() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if suggested.isEmpty {
                            Label("Nothing to clean up", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).padding(.vertical, 4)
                        }
                        ForEach(SweepVerdict.allCases.filter(\.suggested), id: \.self) { verdict in
                            let rows = suggested.filter { $0.verdict == verdict }
                            if !rows.isEmpty { section(verdict, rows) }
                        }
                        if !kept.isEmpty {
                            DisclosureGroup(
                                "Kept · \(countText(kept.count, "group"))",
                                isExpanded: Binding(
                                    get: { showKept || suggested.isEmpty }, set: { showKept = $0 })
                            ) {
                                VStack(spacing: 0) { ForEach(kept) { row($0, showVerdict: true) } }
                                    .padding(.top, 6)
                            }
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 16)
                }
            }
            Divider()
            footer(plan).padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 560, idealHeight: 720)
        .disabled(model.sweepProgress != nil)
        .confirmationDialog(
            "Clean up \(countText(plan.count, "container"))?", isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Clean up", role: .destructive) { Task { await model.cleanUp() } }
        } message: {
            Text(confirmation(plan))
        }
    }

    // The ledger: what the selection does, and the one button that does it.
    private func footer(_ plan: SweepPlan) -> some View {
        HStack(alignment: .center, spacing: 16) {
            if let progress = model.sweepProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    Text(progress.activity).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(plan.memory > 0 ? memoryText(plan.memory) : "\(plan.count)")
                            .font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText()).animation(.snappy, value: plan.count)
                        Text(plan.memory > 0 ? "of memory freed" : plan.count == 1 ? "container" : "containers")
                            .foregroundStyle(.secondary)
                    }
                    Text(summary(plan)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Also remove what it stops", isOn: $model.removeStopped)
                    .toggleStyle(.checkbox).controlSize(.small)
                    .help("Removing keeps volumes; `docker compose up` recreates Compose containers.")
            }
            Button("Done") { model.showingSweep = false }.keyboardShortcut(.cancelAction)
            Button("Clean up \(plan.isEmpty ? "" : countText(plan.count, "container"))…") { confirming = true }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(plan.isEmpty || model.busy || model.sample || model.scanning)
        }
    }

    private func summary(_ plan: SweepPlan) -> String {
        if plan.isEmpty { return "Select the groups to clean up." }
        let stopOnly = plan.stop.filter { stopped in !plan.remove.contains { $0.id == stopped.id } }.count
        let removeOnly = plan.remove.count - (plan.stop.count - stopOnly)
        let both = plan.stop.count - stopOnly
        return [
            both > 0 ? "stops and removes \(both)" : nil,
            stopOnly > 0 ? "stops \(stopOnly)" : nil,
            removeOnly > 0 ? "removes \(removeOnly)" : nil,
        ].compactMap { $0 }.joined(separator: " · ").capitalizedFirst
    }

    private func confirmation(_ plan: SweepPlan) -> String {
        var lines = [summary(plan) + "."]
        if !plan.remove.isEmpty {
            lines.append("Removed containers lose their logs and container files.")
        }
        lines.append("Volumes are kept.")
        return lines.joined(separator: " ")
    }

    private func selected(_ group: SweepGroup) -> Binding<Bool> {
        Binding(
            get: { model.sweepSelection.contains(group.id) },
            set: { on in
                if on { model.sweepSelection.insert(group.id) } else { model.sweepSelection.remove(group.id) }
            })
    }

    private func section(_ verdict: SweepVerdict, _ rows: [SweepGroup]) -> some View {
        let action = rows.first.map(model.sweepAction(for:)) ?? verdict.cleanup
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle(sources: rows.map(selected), isOn: \.self) { EmptyView() }
                    .toggleStyle(.checkbox).labelsHidden()
                    .help("Select every group in this section")
                VerdictPill(verdict: verdict)
                Text(verdict.explanation).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text("\(action.title) · \(countText(rows.count, "group"))").font(.caption.weight(.medium))
                    .foregroundStyle(.secondary).fixedSize()
            }.padding(.bottom, 2)
            VStack(spacing: 0) { ForEach(rows) { row($0, showVerdict: false) } }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func row(_ group: SweepGroup, showVerdict: Bool) -> some View {
        let members = model.members(of: group)
        let running = members.filter(\.running)
        let memory = model.snapshot?.totalMemory(running) ?? 0
        return HStack(spacing: 10) {
            Toggle(isOn: selected(group)) { EmptyView() }.toggleStyle(.checkbox).labelsHidden()
            Image(systemName: group.project == nil ? "shippingbox" : "square.stack.3d.up")
                .foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                    if members.count > 1 {
                        Text("\(members.count) containers").font(.caption).foregroundStyle(.secondary)
                    }
                    if showVerdict { VerdictPill(verdict: group.verdict) }
                }
                Text(group.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(running.isEmpty ? "Stopped" : memoryText(memory))
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Button {
                open(group, members)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }.buttonStyle(.borderless).help("Open")
        }.padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { selected(group).wrappedValue.toggle() }
    }

    private func open(_ group: SweepGroup, _ members: [Container]) {
        model.showingSweep = false
        if let project = group.project {
            model.navigate(.containers, project: project)
        } else if let container = members.first {
            model.openContainer(container.id)
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

struct VerdictPill: View {
    let verdict: SweepVerdict
    private var color: Color {
        switch verdict {
        case .orphan, .stale: return .orange
        case .idle: return .yellow
        case .active: return .green
        case .recent, .stopped: return .secondary
        }
    }
    var body: some View {
        Text(verdict.title).font(.caption.weight(.medium)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.13), in: Capsule())
            .fixedSize()
    }
}
