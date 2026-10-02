import AppKit
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct ResourceOverview: View {
  let snapshot: Snapshot
  var body: some View {
    let memory = snapshot.totalMemory(snapshot.containers)
    let cpu = snapshot.totalCPU(snapshot.containers) / Double(max(1, snapshot.vm.cpus))
    HStack(spacing: 24) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Container CPU").font(.caption).foregroundStyle(.secondary)
        Text(String(format: "%.1f%% of %d CPUs", cpu, snapshot.vm.cpus)).monospacedDigit()
        ProgressView(value: min(1, cpu / 100)).tint(.teal)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("Container memory").font(.caption).foregroundStyle(.secondary)
        Text(memoryText(memory) + " / " + memoryText(Double(snapshot.vm.memory))).monospacedDigit()
        ProgressView(value: min(1, memory / Double(max(1, snapshot.vm.memory)))).tint(.teal)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("Published ports").font(.caption).foregroundStyle(.secondary)
        Text("\(snapshot.containers.flatMap(\.endpoints).count) endpoints").monospacedDigit()
        Text("Select a container to open").font(.caption).foregroundStyle(.secondary)
      }
    }.padding(14).background(
      Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)
    )
    .help(
      "Container totals exclude the VM operating system. CPU is relative to the allocated VM capacity."
    )
  }
}
