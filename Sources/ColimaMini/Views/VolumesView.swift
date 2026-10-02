import ColimaAppState
import ColimaCore
import SwiftUI

struct VolumesView: View {
  @ObservedObject var model: Dashboard
  var visible: [Volume] {
    model.volumes.filter {
      (model.volumeSearch.isEmpty
        || ($0.name + " " + ($0.project ?? "")).localizedCaseInsensitiveContains(model.volumeSearch))
        && (!model.unattachedOnly || $0.attached == false)
        && (model.volumeKind == .all
          || $0.anonymous == (model.volumeKind == .anonymous))
    }.sorted {
      model.volumeSortBySize
        ? ($0.sizeBytes ?? -1) > ($1.sizeBytes ?? -1)
        : $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("Volumes").font(.system(.title, design: .rounded).weight(.semibold))
          Text("Persistent data and the containers that use it").font(.caption).foregroundStyle(
            .secondary)
        }
        Spacer()
        Button("Reclaim space…") { model.openReclaim() }
          .disabled(model.busy || model.sample || model.snapshot?.vm.running != true)
        RefreshButton(busy: model.volumesLoading) { await model.loadVolumes() }
      }
      HStack {
        TextField("Filter volumes or projects", text: $model.volumeSearch).findable(model)
          .textFieldStyle(
            .roundedBorder)
        Picker("Kind", selection: $model.volumeKind) {
          ForEach(VolumeKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).labelsHidden().fixedSize()
          .help("Docker creates anonymous volumes for unnamed mounts, such as an image's VOLUME.")
        Toggle("Unattached only", isOn: $model.unattachedOnly).toggleStyle(.checkbox)
        Picker("Sort", selection: $model.volumeSortBySize) {
          Text("Name").tag(false)
          Text("Size").tag(true)
        }
        .frame(width: 130)
      }
      summary
      Text(
        "Unattached volumes have no container references. Their data may still be important; stopped containers also count as references."
      )
      .font(.caption).foregroundStyle(.secondary)
      if let error = model.volumesError { StatusMessage(text: error) }
      if model.volumesLoading { ProgressView().controlSize(.small) }
      if visible.isEmpty && !model.volumesLoading {
        EmptyPage(
          title: model.volumesError == nil ? "No matching volumes" : "Volumes unavailable",
          message: model.volumesError == nil
            ? "Adjust the filter or start Colima and refresh."
            : "Refresh after the runtime becomes available.", symbol: "externaldrive")
      } else {
        ScrollView {
          LazyVStack(spacing: 1) {
            ForEach(visible) { volume in
              VolumeRow(volume: volume) { model.openVolume(volume.name) }
              Divider()
            }
          }
        }
      }
      if let date = model.volumesDate {
        Text("Measured " + date.formatted(date: .omitted, time: .standard)).font(.caption)
          .foregroundStyle(.secondary)
      }
    }.padding(24).task { await model.loadVolumes() }
  }
}
extension VolumesView {
  @ViewBuilder fileprivate var summary: some View {
    let anonymous = model.volumes.filter { $0.anonymous == true }
    let loose = anonymous.filter { $0.attached == false }
    if !anonymous.isEmpty {
      Text(
        "\(countText(anonymous.count, "anonymous volume")) · \(loose.count) unattached, "
          + bytesText(loose.compactMap(\.sizeBytes).reduce(0, +))
      ).font(.caption).monospacedDigit()
    }
  }
}

struct VolumeDetailView: View {
  @ObservedObject var model: Dashboard
  let name: String
  var volume: Volume? { model.volumes.first { $0.name == name } }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      BackButton(model: model, identifier: "volume.back")
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Text(name).font(.system(.title, design: .rounded).weight(.semibold)).textSelection(
            .enabled)
          if let volume {
            Text("\(bytesText(volume.sizeBytes)) · \(volume.driver)").foregroundStyle(.secondary)
          }
        }
        Spacer()
        RefreshButton(busy: model.volumesLoading) { await model.loadVolumes() }
      }
      if let error = model.volumesError { StatusMessage(text: error) }
      if model.volumesLoading { ProgressView().controlSize(.small) }
      if let volume {
        if let issue = volume.dataIssue { StatusMessage(text: issue) }
        Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 14) {
          GridRow {
            Text("Project").foregroundStyle(.secondary)
            if let project = volume.project {
              Button(project) { model.navigate(.containers, project: project) }.buttonStyle(.link)
            } else {
              Text("No project label")
            }
          }
          GridRow {
            Text("Use").foregroundStyle(.secondary)
            Text(
              volume.attached.map { $0 ? "Attached, including stopped containers" : "Unattached" }
                ?? "Reference data unavailable")
          }
          GridRow {
            Text("Created").foregroundStyle(.secondary)
            Text(timestampText(volume.createdAt))
          }
          if let mountpoint = volume.mountpoint {
            GridRow {
              Text("Path in VM").foregroundStyle(.secondary)
              Text(mountpoint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
          }
        }
        Divider()
        Text("Attached containers").font(.headline)
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(volume.references) { reference in
              Button {
                model.openContainer(reference.containerID)
              } label: {
                HStack {
                  Image(systemName: "shippingbox")
                  VStack(alignment: .leading, spacing: 5) {
                    Text(reference.containerName)
                    Text(reference.destination).font(.system(.caption, design: .monospaced))
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Text(reference.running ? "Running" : "Stopped").font(.caption).foregroundStyle(
                    .secondary)
                  Text(reference.readOnly ? "Read only" : "Read / write").font(.caption)
                    .foregroundStyle(.secondary)
                  Image(systemName: "chevron.right").font(.caption)
                }.padding(12).background(
                  Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
              }.buttonStyle(.plain).accessibilityIdentifier(
                "volume.container." + reference.containerName)
            }
            if volume.references.isEmpty {
              Text(
                volume.referencesAvailable
                  ? "No existing containers reference this volume."
                  : "Container references could not be measured."
              )
              .foregroundStyle(.secondary)
            }
          }
        }
        Text("Data is inside the Colima VM. This page does not delete or edit volume contents.")
          .font(.caption).foregroundStyle(.secondary)
      } else if !model.volumesLoading {
        EmptyPage(
          title: "Volume unavailable",
          message:
            "It may have been removed or the runtime cannot be reached. Return to Volumes and refresh.",
          symbol: "externaldrive")
      }
      Spacer(minLength: 0)
    }.padding(24).task { await model.loadVolumes() }
  }
}

private struct VolumeRow: View {
  let volume: Volume
  let open: () -> Void
  private var subtitle: String {
    var pieces = [volume.driver]
    if let project = volume.project { pieces.insert(project, at: 0) }
    if volume.anonymous == true, let user = volume.references.first {
      pieces.insert(user.containerName, at: 0)
    }
    pieces.append(
      volume.referencesAvailable
        ? countText(volume.references.count, "container reference") : "Reference data unavailable")
    return pieces.joined(separator: " · ")
  }
  private var useDescription: String {
    switch volume.attached {
    case .some(true): return "Attached"
    case .some(false): return "Unattached"
    case .none: return "Use unknown"
    }
  }
  var body: some View {
    Button(action: open) {
      HStack(spacing: 12) {
        Image(systemName: "externaldrive").foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 5) {
          if volume.anonymous == true {
            HStack(spacing: 6) {
              Text("Anonymous").fontWeight(.medium)
              Text(volume.name.prefix(12)).font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            }.help(volume.name)
          } else {
            Text(volume.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
          }
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Text(useDescription).font(.caption).foregroundStyle(.secondary)
        Text(bytesText(volume.sizeBytes)).monospacedDigit().frame(width: 95, alignment: .trailing)
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
      }.padding(12).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier("volume.row." + volume.name)
  }
}
