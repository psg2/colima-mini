import ColimaAppState
import SwiftUI

struct StorageView: View {
  @ObservedObject var model: Dashboard
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text("Storage").font(.system(.title, design: .rounded).weight(.semibold))
            Text("VM capacity, Docker objects and space occupied on your Mac")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          RefreshButton(busy: model.storageLoading) { await model.loadStorage() }
        }
        if let error = model.storageError { StatusMessage(text: error) }
        if model.storageLoading { ProgressView("Measuring storage…").controlSize(.small) }
        if let storage = model.storage {
          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
              Text("Colima data disk").font(.headline)
              Spacer()
              Text(
                "Configured capacity: "
                  + (storage.configuredCapacityBytes.map { bytesText(Double($0)) } ?? "Unavailable")
              )
              .foregroundStyle(.secondary)
            }
            if let filesystem = storage.filesystem {
              Text(bytesText(Double(filesystem.usedBytes)) + " used").font(
                .system(size: 30, weight: .medium, design: .rounded)
              ).monospacedDigit()
              ProgressView(value: Double(filesystem.usedBytes), total: Double(filesystem.sizeBytes))
                .tint(.teal)
              HStack(spacing: 24) {
                Text("Filesystem " + bytesText(Double(filesystem.sizeBytes)))
                Text("Available " + bytesText(Double(filesystem.availableBytes)))
                Text("Reserved blocks " + bytesText(Double(filesystem.reservedBytes)))
              }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
            } else {
              Text("Filesystem usage unavailable").foregroundStyle(.secondary)
            }
            Text(
              "Configured capacity is the virtual disk limit. The filesystem can be smaller because of partitioning and metadata; reserved blocks are excluded from available space."
            )
            .font(.caption).foregroundStyle(.secondary)
            if let error = storage.errors["capacity"] { StatusMessage(text: error) }
            if let error = storage.errors["filesystem"] { StatusMessage(text: error) }
          }
          Divider()
          Text("Docker objects").font(.headline)
          Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
            GridRow {
              Text("Type")
              Text("Objects")
              Text("Used")
              Text("Reclaimable estimate")
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(storage.docker) { category in
              GridRow {
                Text(category.type)
                Text(category.totalCount.map(String.init) ?? "Unknown")
                Text(bytesText(category.sizeBytes)).monospacedDigit()
                Text(bytesText(category.reclaimableBytes)).monospacedDigit()
              }
            }
          }
          if let error = storage.errors["docker"] { StatusMessage(text: error) }
          Text(
            "Docker's categories can share data. Reclaimable is a daemon estimate, not a promise of space recovered on the Mac. Unattached volume data may still matter."
          )
          .font(.caption).foregroundStyle(.secondary)
          Divider()
          Text("Space occupied on Mac").font(.headline)
          Text(storage.hostAllocatedBytes.map { bytesText(Double($0)) } ?? "Unavailable")
            .font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
          Text(
            "Allocated blocks of the data and operating-system disk images. Sparse images can retain space after Docker data is deleted. APFS sharing/compression limits how precisely this predicts recoverable space."
          )
          .font(.caption).foregroundStyle(.secondary)
          if let error = storage.errors["host"] { StatusMessage(text: error) }
          Text("Measured " + storage.measuredAt.formatted(date: .omitted, time: .standard))
            .font(.caption).foregroundStyle(.secondary)
        } else if !model.storageLoading {
          Text("Refresh to measure storage. Colima will not be started automatically.")
            .foregroundStyle(.secondary)
        }
        Divider()
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text("Unused containers").font(.headline)
            Text("Review candidates and their reasons. The report keeps containers and volumes.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Review unused containers") { Task { await model.scan() } }
            .disabled(model.scanning || model.busy || model.snapshot?.vm.running != true)
            .accessibilityIdentifier("storage.sweep")
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
    }.task { await model.loadStorage() }
  }
}
