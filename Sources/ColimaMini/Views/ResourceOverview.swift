import ColimaCore
import SwiftUI

struct ResourceOverview: View {
  let snapshot: Snapshot
  var body: some View {
    HStack(spacing: 24) {
      Text(
        String(
          format: "Container CPU %.1f%% of %d CPUs",
          snapshot.totalCPU(snapshot.containers) / Double(max(1, snapshot.vm.cpus)),
          snapshot.vm.cpus))
      Text(
        "Memory " + memoryText(snapshot.totalMemory(snapshot.containers)) + " / "
          + memoryText(Double(snapshot.vm.memory)))
      let attention = snapshot.containers.filter(\.needsAttention).count
      if attention > 0 {
        Label(
          attention == 1 ? "1 needs attention" : "\(attention) need attention",
          systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.orange)
      }
      Spacer()
    }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
      .help(
        "All container totals exclude the VM operating system. Overall CPU is relative to VM capacity; row CPU is 100% per core."
      )
  }
}
