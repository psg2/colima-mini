import ColimaAppState
import ColimaCore
import SwiftUI

// Usage totals live in the status bar; the list header only flags failures
// and offers to act on all of them at once.
struct ResourceOverview: View {
    @ObservedObject var model: Dashboard
    var body: some View {
        let attention = model.attention
        let failed = model.failedStopped
        if !attention.isEmpty {
            HStack(spacing: 10) {
                Label(
                    attention.count == 1 ? "1 needs attention" : "\(attention.count) need attention",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                Button("Select all") { model.checkAttention() }.buttonStyle(.link)
                    .help("Check every failed container for a bulk action")
                    .disabled(attention.allSatisfy { model.checked.contains($0.id) })
                if !failed.isEmpty {
                    Button("Remove \(failed.count) stopped…") { model.requestRemoveFailed() }
                        .buttonStyle(.link)
                        .help("Remove the failed containers that are no longer running. Volumes are kept.")
                        .disabled(model.busy || model.sample)
                        .accessibilityIdentifier("attention.remove")
                }
                Spacer()
            }.font(.caption)
        }
    }
}

// Below a capped "Needs attention" list: how many were left out, and one
// confirmed removal of every failed container that has stopped. `showAll`
// opens the container list, which has the full set.
struct AttentionFooter: View {
    @ObservedObject var model: Dashboard
    let limit: Int
    let showAll: () -> Void
    var body: some View {
        let hidden = model.attention.count - limit
        let failed = model.failedStopped
        if hidden > 0 || failed.count > 1 {
            HStack(spacing: 10) {
                if hidden > 0 { Button("Show \(hidden) more", action: showAll).buttonStyle(.link) }
                Spacer()
                if failed.count > 1 {
                    Button("Remove \(failed.count) stopped…") {
                        showAll()
                        model.requestRemoveFailed()
                    }
                    .help("Remove the failed containers that are no longer running. Volumes are kept.")
                    .disabled(model.busy || model.sample)
                }
            }.font(.caption).controlSize(.small)
        }
    }
}
