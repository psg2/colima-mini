import AppKit
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct ProjectActions: View {
  @ObservedObject var model: Dashboard
  let containers: [Container]
  var body: some View {
    Menu {
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
      if let folder = containers.compactMap(\.folder).first {
        Divider()
        Button("Open project folder") { NSWorkspace.shared.open(folder) }
      }
    } label: {
      Image(systemName: "ellipsis")
    }
    .menuStyle(.borderlessButton).fixedSize().help("Project actions")
    .disabled(model.busy || model.sample || containers.isEmpty)
  }
}
