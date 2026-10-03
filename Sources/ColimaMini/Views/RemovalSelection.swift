import SwiftUI

// Leading mark for a removable row: its icon until the row is hovered or
// something is selected, then a checkbox. Rows that can't be removed keep
// the icon.
struct SelectionMark<Icon: View>: View {
    let name: String
    let selectable: Bool
    let selected: Bool
    let selecting: Bool
    let hovering: Bool
    let toggle: () -> Void
    @ViewBuilder let icon: () -> Icon
    var body: some View {
        if selectable && (hovering || selecting) {
            Button(action: toggle) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)
            }.buttonStyle(.plain).help(selected ? "Deselect" : "Select for removal (⌘-click)")
                .accessibilityLabel(selected ? "Deselect \(name)" : "Select \(name)")
        } else {
            icon()
        }
    }
}

// Shown while rows are selected: how many, how much space removal frees at
// most, and one confirmed Remove.
struct RemovalBar: View {
    let count: Int
    let noun: String
    let bytes: Double
    let bytesNote: String
    let disabled: Bool
    let selectAll: (() -> Void)?
    let clear: () -> Void
    let remove: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Text("\(countText(count, noun)) selected").fontWeight(.medium)
            Text("· up to \(bytesText(bytes)) \(bytesNote)").foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button("Remove \(count)…", action: remove).disabled(disabled)
            Divider().frame(height: 16)
            if let selectAll { Button("Select all unused", action: selectAll) }
            Button("Clear", action: clear).keyboardShortcut(.cancelAction)
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
