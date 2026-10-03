import ColimaAppState
import ColimaCore
import SwiftUI

// The scan suggests; the user acts per group. Rows follow the live container
// list, so a stopped group offers removal next and a removed one disappears.
struct UnusedContainersView: View {
    @ObservedObject var model: Dashboard
    @State private var showKept = false
    private var groups: [SweepGroup] {
        (model.sweepGroups ?? []).filter { !model.members(of: $0).isEmpty }
    }
    private var suggested: [SweepGroup] { groups.filter(\.verdict.suggested) }
    private var kept: [SweepGroup] { groups.filter { !$0.verdict.suggested } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Unused containers").font(.title2.weight(.semibold))
                Spacer()
                if model.scanning || model.busy { ProgressView().controlSize(.small) }
                Button {
                    Task { await model.scan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("Scan again").disabled(model.scanning || model.busy)
            }
            Text(
                "Each Compose project is checked for clients on its published ports, network traffic and recent log lines. Nothing changes until you choose an action, and volumes are always kept."
            ).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = model.sweepError { StatusMessage(text: error) }
            if model.sweepGroups == nil {
                if model.scanning {
                    ProgressView("Checking clients, traffic and logs…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
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
                                VStack(spacing: 6) { ForEach(kept) { row($0, showVerdict: true) } }.padding(.top, 6)
                            }
                        }
                    }
                }
            }
            HStack {
                if let at = model.sweptAt {
                    Text("Scanned \(at.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { model.showingSweep = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 760, height: 560)
            .confirmationDialog(
                model.pending?.title ?? "Confirm action",
                isPresented: Binding(
                    get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }),
                titleVisibility: .visible
            ) {
                if let action = model.pending {
                    Button(action.label, role: action.destructive ? .destructive : nil) {
                        Task { await model.perform(action) }
                    }
                }
            } message: {
                Text(model.pending?.message ?? "")
            }
    }

    private func section(_ verdict: SweepVerdict, _ rows: [SweepGroup]) -> some View {
        let members = rows.flatMap { model.members(of: $0) }
        let running = members.filter(\.running)
        let stopped = members.filter { !$0.running }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VerdictPill(verdict: verdict)
                Text(verdict.explanation).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if rows.count > 1 {
                    if !running.isEmpty {
                        Button("Stop all") { model.request("stop", containers: running) }
                    } else if !stopped.isEmpty {
                        Button("Remove all…") { model.request("rm", containers: stopped) }
                    }
                }
            }.controlSize(.small).disabled(model.busy || model.sample)
            ForEach(rows) { row($0, showVerdict: false) }
        }
    }

    private func row(_ group: SweepGroup, showVerdict: Bool) -> some View {
        let members = model.members(of: group)
        let running = members.filter(\.running)
        let stopped = members.filter { !$0.running }
        return HStack(spacing: 10) {
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
                Text(
                    running.isEmpty || stopped.isEmpty
                        ? group.reason : "\(running.count) running · \(group.reason)"
                )
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Open") { open(group, members) }
            if !running.isEmpty {
                Button("Stop") { model.request("stop", containers: running) }
                    .disabled(model.busy || model.sample)
            } else if !stopped.isEmpty {
                Button("Remove…") { model.request("rm", containers: stopped) }
                    .disabled(model.busy || model.sample)
            }
        }.controlSize(.small).padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
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
