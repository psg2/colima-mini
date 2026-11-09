import ColimaAppState
import ColimaCore
import SwiftUI

// Confirms an action on more containers than a system dialog can show. The
// list scrolls and names exactly what the action touches, grouped by project.
struct ConfirmContainersView: View {
    @ObservedObject var model: Dashboard
    let action: PendingAction
    private var projects: [(name: String, containers: [Container])] {
        Dictionary(grouping: action.containers, by: \.project)
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
            .sorted { ($0.name == "Standalone" ? 1 : 0, $0.name) < ($1.name == "Standalone" ? 1 : 0, $1.name) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(action.title).font(.title2.weight(.semibold))
                Text(action.message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding([.horizontal, .top], 24).padding(.bottom, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(projects, id: \.name) { project in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(project.name) · \(project.containers.count)")
                                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            VStack(spacing: 0) {
                                ForEach(project.containers) { row($0) }
                            }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.padding(.horizontal, 24).padding(.bottom, 16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.pending = nil }.keyboardShortcut(.cancelAction)
                Button(action.label, role: .destructive) { Task { await model.perform(action) } }
                    .tint(.red).buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("confirm.containers")
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 420, idealHeight: 600)
    }
    private func row(_ container: Container) -> some View {
        HStack(spacing: 10) {
            Circle().fill(container.running ? Color.green : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(container.name).lineLimit(1).truncationMode(.middle)
                Text(container.image).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(container.running ? "Running" : container.state.capitalized).font(.caption)
                .foregroundStyle(.secondary)
        }.padding(.horizontal, 10).padding(.vertical, 6)
    }
}
