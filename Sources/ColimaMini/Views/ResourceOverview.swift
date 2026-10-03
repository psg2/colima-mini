import ColimaCore
import SwiftUI

// Usage totals live in the status bar; the list header only flags failures.
struct ResourceOverview: View {
    let snapshot: Snapshot
    var body: some View {
        let attention = snapshot.containers.filter(\.needsAttention).count
        if attention > 0 {
            HStack {
                Label(
                    attention == 1 ? "1 needs attention" : "\(attention) need attention",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                Spacer()
            }.font(.caption)
        }
    }
}
