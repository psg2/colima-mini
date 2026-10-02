import ColimaAppState
import ColimaCore
import SwiftUI

// Preview first, remove second: the sheet lists every candidate and removes only
// the categories the user leaves checked.
struct ReclaimView: View {
  @ObservedObject var model: Dashboard
  @State private var selected = Set(CleanupKind.allCases.filter(\.safeByDefault))
  @State private var confirming = false
  private var plan: CleanupPlan? { model.cleanupPlan }
  private var chosen: [CleanupCategory] {
    plan?.categories.filter { selected.contains($0.kind) && !$0.items.isEmpty } ?? []
  }
  private var chosenCount: Int { chosen.map(\.items.count).reduce(0, +) }
  private var chosenBytes: Double { chosen.map(\.bytes).reduce(0, +) }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Reclaim space").font(.title2.weight(.semibold))
        Spacer()
        if model.cleanupLoading || model.reclaiming { ProgressView().controlSize(.small) }
        Button {
          Task { await model.loadCleanupPlan() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }.help("Measure again").disabled(model.cleanupLoading || model.reclaiming)
      }
      Text(
        "Only the items listed here are removed, one by one and without force. Docker refuses anything that started or gained a container since this preview. Named volumes are never removed."
      ).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if let result = model.cleanupResult { summary(result) }
      if let error = model.cleanupError { StatusMessage(text: error) }
      if let plan {
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(plan.categories.filter { !$0.items.isEmpty }) { row($0) }
            let empty = plan.categories.filter(\.items.isEmpty)
            if !empty.isEmpty {
              Text("Nothing to remove: " + empty.map(\.kind.title).joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
          }
        }
        Text(
          "Measured \(plan.measuredAt.formatted(date: .omitted, time: .standard)). Sizes are Docker's estimates; shared layers and build cache can reclaim less."
        ).font(.caption).foregroundStyle(.secondary)
      } else if model.cleanupLoading {
        ProgressView("Measuring Docker objects…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Spacer()
      }
      HStack {
        Button("Done") { model.showingReclaim = false }.keyboardShortcut(.cancelAction)
        Spacer()
        Text(
          chosenCount == 0
            ? "Nothing selected"
            : "\(countText(chosenCount, "item")) · up to \(bytesText(chosenBytes))"
        ).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        Button("Remove…") { confirming = true }
          .buttonStyle(.borderedProminent).tint(.red)
          .disabled(chosenCount == 0 || model.busy || model.sample || model.cleanupLoading)
          .accessibilityIdentifier("reclaim.remove")
      }
    }.padding(24).frame(width: 720, height: 600)
      .task { await model.loadCleanupPlan() }
      .confirmationDialog(
        "Remove \(countText(chosenCount, "item"))?", isPresented: $confirming,
        titleVisibility: .visible
      ) {
        Button("Remove", role: .destructive) {
          let kinds = Set(chosen.map(\.kind))
          Task { await model.reclaim(kinds) }
        }
      } message: {
        Text(
          chosen.map { "\($0.kind.title): \($0.items.count)" }.joined(separator: "\n")
            + "\n\nThis can't be undone.")
      }
  }

  private func row(_ category: CleanupCategory) -> some View {
    let empty = category.items.isEmpty
    return VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Toggle(
          isOn: Binding(
            get: { selected.contains(category.kind) && !empty },
            set: { on in
              if on { selected.insert(category.kind) } else { selected.remove(category.kind) }
            })
        ) {
          Text(category.kind.title).fontWeight(.medium)
        }.toggleStyle(.checkbox).disabled(empty)
          .accessibilityIdentifier("reclaim." + category.kind.rawValue)
        if !category.kind.safeByDefault && !empty {
          Text("Review").font(.caption2.weight(.medium)).foregroundStyle(.orange)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.orange.opacity(0.13), in: Capsule())
        }
        Spacer()
        Text(empty ? "None" : countText(category.items.count, "item")).foregroundStyle(.secondary)
        Text(empty ? "" : bytesText(category.bytes)).monospacedDigit()
          .frame(width: 90, alignment: .trailing)
      }
      Text(category.kind.explanation).font(.caption).foregroundStyle(.secondary)
        .padding(.leading, 20)
      if !empty {
        DisclosureGroup("Show items") {
          VStack(alignment: .leading, spacing: 3) {
            ForEach(category.items) { item in
              HStack {
                Text(item.name).font(.system(.caption, design: .monospaced)).lineLimit(1)
                  .truncationMode(.middle).help(item.id)
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(bytesText(item.bytes)).font(.caption).monospacedDigit()
              }
            }
          }.padding(.top, 4)
        }.font(.caption).padding(.leading, 20)
      }
    }.padding(12).opacity(empty ? 0.55 : 1)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
  }

  private func summary(_ result: CleanupResult) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(
        "Removed \(countText(result.removedCount, "item")) · about \(bytesText(result.reclaimedBytes)) reclaimed",
        systemImage: "checkmark.circle.fill"
      ).foregroundStyle(.green)
      ForEach(result.failures, id: \.self) { failure in
        Text(failure).font(.caption).foregroundStyle(.orange).lineLimit(2)
      }
      if !result.failures.isEmpty {
        Text("Docker refused these items, usually because something uses them now.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
  }
}
