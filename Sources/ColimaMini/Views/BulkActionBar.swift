import ColimaAppState
import ColimaCore
import SwiftUI

// Shown while containers are checked. Each action applies to the checked
// containers it fits (Stop to running ones, Remove to stopped ones) and asks first.
struct BulkActionBar: View {
    @ObservedObject var model: Dashboard
    var body: some View {
        let checked = model.checkedContainers
        let running = checked.filter(\.running)
        let stopped = checked.filter { !$0.running }
        HStack(spacing: 8) {
            Text("\(countText(checked.count, "container")) selected").fontWeight(.medium)
            Spacer()
            Group {
                Button("Start \(stopped.count)") { model.request("start", containers: stopped) }
                    .disabled(stopped.isEmpty)
                Button("Stop \(running.count)") { model.request("stop", containers: running) }
                    .disabled(running.isEmpty)
                Button("Restart \(running.count)") { model.request("restart", containers: running) }
                    .disabled(running.isEmpty)
                Button("Remove \(stopped.count)…") { model.request("rm", containers: stopped) }
                    .disabled(stopped.isEmpty)
            }.disabled(model.busy || model.sample)
            Divider().frame(height: 16)
            Button("Select all") { model.checked.formUnion(model.visible.map(\.id)) }
                .disabled(model.visible.allSatisfy { model.checked.contains($0.id) })
            Button("Clear") { model.checked.removeAll() }.keyboardShortcut(.cancelAction)
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
