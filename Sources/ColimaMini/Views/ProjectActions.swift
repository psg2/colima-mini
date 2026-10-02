import AppKit
import ColimaAppState
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct ProjectActions: View {
  @ObservedObject var model: Dashboard
  let containers: [Container]
  var body: some View {
    Menu {
      if let project = containers.first?.project, containers.contains(where: \.running) {
        Button("Show logs") { model.openProjectLogs(project) }
        Divider()
      }
      Self.items(model: model, containers: containers)
      if let project = containers.first?.project,
        containers.allSatisfy({ $0.project == project }),
        containers.first?.label("com.docker.compose.project") != nil
      {
        Divider()
        Self.composeItems(
          model: model, project: project, folderExists: containers.first?.origin?.exists() == true)
      }
      if let origin = containers.lazy.compactMap(\.origin).first {
        Divider()
        OriginMenuItems(model: model, origin: origin)
      }
    } label: {
      Image(systemName: "ellipsis")
    }
    .menuStyle(.borderlessButton).fixedSize().help("Project actions")
    .disabled(model.busy || containers.isEmpty)
  }
  @ViewBuilder static func composeItems(model: Dashboard, project: String, folderExists: Bool)
    -> some View
  {
    Section("Compose") {
      Button("Up") { model.requestCompose(.up, project: project) }.disabled(!folderExists)
      Button("Pull images") { model.requestCompose(.pull, project: project) }
        .disabled(!folderExists)
      Button("Down…") { model.requestCompose(.down, project: project) }
      Button("Down and delete volumes…") { model.requestCompose(.downVolumes, project: project) }
    }.disabled(model.sample || model.busy)
  }
  @ViewBuilder static func items(model: Dashboard, containers: [Container]) -> some View {
    Group {
      Button("Start containers") {
        model.request("start", containers: containers.filter { !$0.running })
      }
      .disabled(containers.allSatisfy(\.running))
      Button("Stop containers") { model.request("stop", containers: containers.filter(\.running)) }
        .disabled(!containers.contains(where: \.running))
      Button("Restart containers") {
        model.request("restart", containers: containers.filter(\.running))
      }
      .disabled(!containers.contains(where: \.running))
    }.disabled(model.sample)
  }
}
