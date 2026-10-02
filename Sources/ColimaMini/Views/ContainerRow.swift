import AppKit
import ColimaAppState
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct ContainerRow: View {
  @ObservedObject var model: Dashboard
  let container: Container
  let showProject: Bool
  var body: some View {
    Button {
      model.openContainer(container.id)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: container.needsAttention ? "exclamationmark.triangle" : "shippingbox")
          .foregroundStyle(container.needsAttention ? Color.orange : Color.secondary)
        VStack(alignment: .leading, spacing: 3) {
          Text(container.service).fontWeight(.medium).lineLimit(1)
          Text(
            showProject
              ? container.project + " · " + container.image
              : container.name + " · " + container.image
          )
          .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }.frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 5) {
          Circle().fill(
            container.needsAttention
              ? Color.orange : container.running ? Color.green : Color.secondary
          )
          .frame(width: 6, height: 6)
          Text(container.status).font(.caption).lineLimit(1)
        }.frame(width: 150, alignment: .leading)
        Text(model.snapshot?.metric(for: container)?.cpuPercent ?? "—")
          .frame(width: 65, alignment: .trailing).monospacedDigit()
        Text(model.snapshot?.metric(for: container).map { memoryText($0.memoryBytes) } ?? "—")
          .frame(width: 90, alignment: .trailing).monospacedDigit()
      }.padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(
          model.selectedID == container.id ? Color.accentColor.opacity(0.18) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }.buttonStyle(.plain).help(container.name + " · " + container.status)
      .accessibilityIdentifier("container.row." + container.name)
  }
}
