import AppKit
import ColimaAppState
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct ContainerList: View {
  @ObservedObject var model: Dashboard
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(model.grouped ? "Project / service" : "Container").frame(
          maxWidth: .infinity, alignment: .leading)
        Text("Status").frame(width: 150, alignment: .leading)
        Text("CPU").frame(width: 65, alignment: .trailing)
        Text("Memory").frame(width: 90, alignment: .trailing)
      }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 36).padding(.vertical, 8)
      ScrollView {
        LazyVStack(spacing: 10) {
          if model.visible.isEmpty {
            VStack(spacing: 8) {
              Image(systemName: "line.3.horizontal.decrease.circle").font(.title)
              Text(
                model.snapshot?.vm.running == false ? "Colima is stopped" : "No matching containers"
              )
              Text("Adjust the search or running filter to see more.").font(.caption)
                .foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(36)
          } else if model.grouped {
            ForEach(Array(Set(model.visible.map(\.project))).sorted(), id: \.self) { project in
              ProjectSection(
                model: model, project: project,
                containers: model.visible.filter { $0.project == project })
            }
          } else {
            ForEach(model.visible) { ContainerRow(model: model, container: $0, showProject: true) }
          }
        }.scrollTargetLayout().padding(.horizontal, 12).padding(.bottom, 12)
      }.scrollPosition(id: $model.listScrollID)
    }
  }
}
