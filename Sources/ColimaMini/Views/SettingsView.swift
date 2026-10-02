import AppKit
import ColimaAppState
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: Dashboard
  @State private var cpus = 10.0
  @State private var memory = 20.0
  @State private var saved: ResourceSettings?
  @State private var error: String?
  @State private var confirming = false
  var proposed: ResourceSettings { ResourceSettings(cpus: Int(cpus), memoryGiB: memory) }
  var changed: Bool { saved != nil && proposed != saved }
  var differsFromVM: Bool {
    guard let vm = model.snapshot?.vm else { return false }
    return proposed.cpus != vm.cpus
      || abs(proposed.memoryGiB - Double(vm.memory) / 1_073_741_824) > 0.01
  }
  func load() {
    do {
      let value = try model.backend.settings()
      saved = value
      cpus = Double(value.cpus)
      memory = value.memoryGiB
      error = nil
    } catch { self.error = error.localizedDescription }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        if let icon = NSApp.applicationIconImage {
          Image(nsImage: icon).resizable().frame(width: 48, height: 48)
        }
        VStack(alignment: .leading, spacing: 3) {
          Text("Settings").font(.title2.weight(.semibold))
          Text("Default Colima profile").foregroundStyle(.secondary)
        }
        Spacer()
        if model.sample {
          Text("Sample · changes disabled").font(.caption).foregroundStyle(.orange)
        }
      }
      GroupBox("Virtual machine resources") {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("CPU cores")
            Spacer()
            Text("\(Int(cpus)) of \(ResourceSettings.hostCPUs)").monospacedDigit()
          }
          Slider(value: $cpus, in: 1...Double(max(2, ResourceSettings.hostCPUs)), step: 1)
            .accessibilityLabel("CPU cores").accessibilityIdentifier("settings.cpu")
          HStack {
            Text("Memory")
            Spacer()
            Text(String(format: "%.1f GiB of %d GiB", memory, ResourceSettings.hostMemory))
              .monospacedDigit()
          }
          Slider(
            value: Binding(get: { memory }, set: { memory = ($0 * 2).rounded() / 2 }),
            in: 1...Double(max(2, ResourceSettings.hostMemory))
          )
          .accessibilityLabel("Memory in GiB").accessibilityIdentifier("settings.memory")
          HStack {
            Text("Presets").font(.caption).foregroundStyle(.secondary)
            Button("Light") {
              cpus = min(2, Double(ResourceSettings.hostCPUs))
              memory = min(4, Double(ResourceSettings.hostMemory))
            }
            Button("Balanced") {
              cpus = min(6, Double(ResourceSettings.hostCPUs))
              memory = min(12, Double(ResourceSettings.hostMemory))
            }
            Button("Heavy") {
              cpus = min(10, Double(ResourceSettings.hostCPUs))
              memory = min(20, Double(ResourceSettings.hostMemory))
            }
          }
          Divider()
          if let vm = model.snapshot?.vm {
            Text("Current VM: " + vm.allocation).font(.caption).foregroundStyle(.secondary)
            if !changed && differsFromVM {
              Text("Saved changes are waiting for the next start.").font(.caption).foregroundStyle(
                .orange)
            }
          }
          Text(
            "Saving keeps the VM running. Applying now restarts Colima and restores containers that were running. Volumes are kept."
          )
          .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(10)
      }.disabled(model.busy || saved == nil)
      HStack {
        Button("Revert") {
          load()
          model.settingsMessage = nil
        }.disabled(!changed || model.busy)
        Spacer()
        Button("Save for next start") {
          Task {
            await model.changeResources(proposed, restart: false)
            load()
          }
        }
        .disabled(!changed || model.busy || model.sample).accessibilityIdentifier("settings.save")
        Button(model.snapshot?.vm.running == true ? "Apply & restart…" : "Apply & start…") {
          confirming = true
        }
        .disabled(saved == nil || !(changed || differsFromVM) || model.busy || model.sample)
        .accessibilityIdentifier("settings.apply")
      }
      if let message = error ?? model.settingsMessage {
        Text(message).font(.callout).textSelection(.enabled)
          .foregroundStyle(
            error != nil || message.hasPrefix("Could not") ? Color.orange : Color.secondary)
      }
      if model.applyingResources {
        HStack {
          ProgressView().controlSize(.small)
          Text("Applying resources…").font(.caption)
        }
      }
      GroupBox("Dashboard") {
        HStack {
          Text("Refresh interval")
          Spacer()
          Picker("Refresh interval", selection: $model.refreshInterval) {
            ForEach([5, 10, 30, 60], id: \.self) { Text("\($0) seconds").tag($0) }
          }.labelsHidden().frame(width: 150)
        }.padding(10)
      }
      Text("Context: colima · CPU and memory changes stay in your local Colima profile.")
        .font(.caption).foregroundStyle(.secondary)
    }.padding(24).frame(width: 570)
      .onAppear { load() }
      .onChange(of: model.refreshInterval) { _, _ in model.savePreferences() }
      .confirmationDialog(
        "Apply resource changes?", isPresented: $confirming, titleVisibility: .visible
      ) {
        Button(
          model.snapshot?.vm.running == true ? "Restart Colima" : "Start Colima", role: .destructive
        ) {
          Task {
            await model.changeResources(proposed, restart: true)
            load()
          }
        }
      } message: {
        Text(
          "Use \(Int(cpus)) CPUs and \(String(format: "%.1f", memory)) GiB. Running containers will be interrupted while the VM restarts."
        )
      }
  }
}
