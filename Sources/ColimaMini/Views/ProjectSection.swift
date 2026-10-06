import AppKit
import ColimaAppState
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct ProjectSection: View {
    @ObservedObject var model: Dashboard
    let project: String
    let containers: [Container]
    var origin: ProjectOrigin? { containers.lazy.compactMap(\.origin).first }
    var expanded: Binding<Bool> {
        Binding(
            get: { !model.search.isEmpty || !model.collapsed.contains(project) },
            set: { value in
                model.setGroupExpanded(project, expanded: value)
            })
    }
    var body: some View {
        DisclosureGroup(isExpanded: expanded) {
            VStack(spacing: 1) {
                ForEach(containers) { container in
                    ContainerRow(model: model, container: container, showProject: false)
                }
            }.padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: project == "Standalone" ? "shippingbox" : "square.stack.3d.up.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(project).font(.headline).lineLimit(1).truncationMode(.middle)
                        if let origin, model.orphanedProjects.contains(project) {
                            Text("Folder missing").font(.caption2.weight(.medium)).foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.13), in: Capsule())
                                .help("\(origin.displayPath) no longer exists. The worktree may have been removed.")
                        }
                    }
                    HStack(spacing: 4) {
                        Text("\(containers.filter(\.running).count) of \(containers.count) running")
                        if let origin {
                            Text("·")
                            Label(origin.summary, systemImage: origin.kind.symbol).lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }.font(.caption).foregroundStyle(.secondary).help(origin?.displayPath ?? "")
                }
                if containers.contains(where: \.needsAttention) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(
                        "A container needs attention")
                }
                Spacer()
                Text(String(format: "%.2f%%", model.snapshot?.totalCPU(containers) ?? 0))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Text(memoryText(model.snapshot?.totalMemory(containers) ?? 0))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(
                        width: 85, alignment: .trailing)
                ProjectActions(model: model, containers: containers)
            }.padding(.vertical, 5)
        }.padding(10).background(
            Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)
        )
        .accessibilityIdentifier("project.group." + project)
    }
}
