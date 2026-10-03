import ColimaAppState
import SwiftUI

struct RefreshButton: View {
    let busy: Bool
    let action: () async -> Void
    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }.disabled(busy).keyboardShortcut("r", modifiers: .command)
    }
}
struct StatusMessage: View {
    let text: String
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(text).textSelection(.enabled)
            Spacer()
        }.font(.callout).padding(12).background(Color.orange.opacity(0.08))
    }
}
struct EmptyPage: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

// Names the page it returns to; Escape does the same.
struct BackButton: View {
    @ObservedObject var model: Dashboard
    let identifier: String
    var body: some View {
        Button {
            model.goBack()
        } label: {
            Label(model.backTitle, systemImage: "chevron.left").lineLimit(1)
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .help("Back to \(model.backTitle) (⌘[ or Esc)")
        .accessibilityIdentifier(identifier)
    }
}
