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
      Self.items(model: model, containers: containers)
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
