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
struct CleanupReportView: View {
  @ObservedObject var model: Dashboard
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Unused containers").font(.title2)
        Spacer()
        if model.scanning { ProgressView() }
      }
      Text(
        "Report only. Volumes and containers are kept. Unavailable probes cannot prove that a container is idle."
      )
      .font(.callout).foregroundStyle(.secondary)
      ConsoleText(text: model.sweepReport)
      HStack {
        Button("Scan again") { Task { await model.scan() } }.disabled(model.scanning || model.busy)
        Spacer()
        Button("Done") { model.showingSweep = false }.keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 780, height: 440)
  }
}
