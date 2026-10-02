import ColimaAppState
import ColimaCore
import SwiftUI

struct ImagesView: View {
  @ObservedObject var model: Dashboard
  @AppStorage("imageSortBySize") private var sortBySize = false
  @State private var unusedOnly = false
  @State private var removing: DockerImage?
  var visible: [DockerImage] {
    model.images.filter {
      (model.imageSearch.isEmpty
        || ($0.name + " " + $0.imageID).localizedCaseInsensitiveContains(model.imageSearch))
        && (!unusedOnly || $0.unused)
    }.sorted {
      sortBySize
        ? ($0.sizeBytes ?? -1) > ($1.sizeBytes ?? -1)
        : $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("Images").font(.system(.title, design: .rounded).weight(.semibold))
          Text("Image sizes and the containers that use them").font(.caption).foregroundStyle(
            .secondary)
        }
        Spacer()
        Button("Reclaim space…") { model.openReclaim() }
          .disabled(model.busy || model.sample || model.snapshot?.vm.running != true)
        RefreshButton(busy: model.imagesLoading) { await model.loadImages() }
      }
      HStack {
        TextField("Filter images", text: $model.imageSearch).findable(model)
          .textFieldStyle(.roundedBorder)
        Toggle("Unused only", isOn: $unusedOnly).toggleStyle(.checkbox)
        Picker("Sort", selection: $sortBySize) {
          Text("Name").tag(false)
          Text("Size").tag(true)
        }.frame(width: 130)
      }
      if !model.images.isEmpty {
        let unused = model.images.filter(\.unused)
        Text(
          "\(countText(model.images.count, "image")) · \(unused.count) unused, \(bytesText(unused.compactMap(\.uniqueBytes).reduce(0, +))) in their own layers"
        ).font(.caption).foregroundStyle(.secondary)
      }
      if let error = model.imagesError { StatusMessage(text: error) }
      if let activity = model.imageActivity {
        HStack {
          ProgressView().controlSize(.small)
          Text(activity).font(.callout)
        }
      } else if model.imagesLoading {
        ProgressView().controlSize(.small)
      }
      ScrollView {
        LazyVStack(spacing: 1) {
          ForEach(visible) { image in
            row(image)
            Divider()
          }
          if visible.isEmpty && !model.imagesLoading {
            Text(model.imagesError == nil ? "No matching images." : "Image inventory unavailable.")
              .foregroundStyle(.secondary).padding(30)
          }
        }
      }
      Text("Image virtual sizes include shared layers. Use Storage for daemon totals.").font(
        .caption
      ).foregroundStyle(.secondary)
    }.padding(24).task { await model.loadImages() }
      .confirmationDialog(
        "Remove \(removing?.name ?? "image")?",
        isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
        titleVisibility: .visible
      ) {
        if let image = removing {
          Button("Remove", role: .destructive) {
            Task { await model.changeImage(image, pull: false) }
          }
        }
      } message: {
        Text(
          "Removes this tag, and the image once no tag is left. Docker refuses if a container still uses it. Pull downloads it again."
        )
      }
  }

  private func row(_ image: DockerImage) -> some View {
    HStack(spacing: 12) {
      ImageIcon(profile: ImageProfile(image: image.name))
      VStack(alignment: .leading, spacing: 5) {
        Text(image.name).fontWeight(.medium)
        Text(
          image.referencesAvailable
            ? (image.containerIDs.isEmpty
              ? "Unused" : countText(image.containerIDs.count, "container"))
            : "Container use unavailable"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Text(bytesText(image.sizeBytes)).monospacedDigit()
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
    }.padding(12).contentShape(Rectangle())
      .onTapGesture { model.openImage(image.id) }
      .contextMenu {
        Button("Open") { model.openImage(image.id) }
        Button("Pull latest") { Task { await model.changeImage(image, pull: true) } }
          .disabled(image.reference != image.name || model.busy || model.sample)
        Button("Remove…") { removing = image }
          .disabled(!image.unused || model.busy || model.sample)
        Divider()
        Button("Copy name") { Launcher.copy(image.name) }
      }
      .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
      .accessibilityAction { model.openImage(image.id) }
      .accessibilityIdentifier("image.row." + image.name)
  }
}
struct ImageDetailView: View {
  @ObservedObject var model: Dashboard
  let id: String
  var image: DockerImage? { model.images.first { $0.id == id } }
  @State private var confirmingRemoval = false
  @State private var removed = false
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      BackButton(model: model, identifier: "image.back")
      if let image {
        HStack {
          ImageIcon(profile: ImageProfile(image: image.name))
          Text(image.name).font(.system(.title, design: .rounded).weight(.semibold))
          Spacer()
          if let activity = model.imageActivity {
            ProgressView().controlSize(.small)
            Text(activity).font(.caption).foregroundStyle(.secondary)
          }
          Button("Pull latest") { Task { await model.changeImage(image, pull: true) } }
            .disabled(image.reference != image.name || model.busy || model.sample)
            .help("docker pull \(image.name)")
          Button("Remove…") { confirmingRemoval = true }
            .disabled(!image.unused || model.busy || model.sample)
            .help(image.unused ? "Remove this image" : "Containers still use this image")
        }
        .confirmationDialog(
          "Remove \(image.name)?", isPresented: $confirmingRemoval, titleVisibility: .visible
        ) {
          Button("Remove", role: .destructive) {
            removed = true
            Task { await model.changeImage(image, pull: false) }
          }
        } message: {
          Text("Docker refuses if a container still uses it. Pull downloads it again.")
        }
        Text(image.imageID).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
          .textSelection(.enabled)
        HStack(spacing: 30) {
          imageSize("Virtual size", image.sizeBytes)
          imageSize("Shared layers", image.sharedBytes)
          imageSize("Unique layers", image.uniqueBytes)
        }
        Divider()
        Text("Containers using this image").font(.headline)
        if !image.referencesAvailable {
          StatusMessage(
            text: "Container references could not be measured. Refresh Images to retry.")
        }
        ForEach(model.containers.filter { image.containerIDs.contains($0.id) }) { container in
          Button {
            model.openContainer(container.id)
          } label: {
            HStack {
              Label(container.name, systemImage: "shippingbox")
              Spacer()
              Text(container.status).font(.caption).foregroundStyle(.secondary)
              Image(systemName: "chevron.right").font(.caption)
            }.padding(12).background(
              Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
          }.buttonStyle(.plain)
        }
        if image.referencesAvailable && image.containerIDs.isEmpty {
          Text("No existing containers use this image.").foregroundStyle(.secondary)
        }
        Text(
          "Shared layers may belong to more than one image. Removing an image's virtual size would not recover that amount of Mac storage."
        )
        .font(.caption).foregroundStyle(.secondary)
      } else {
        EmptyPage(
          title: "Image unavailable", message: "Return to Images and refresh.",
          symbol: "square.3.layers.3d")
      }
      Spacer()
    }.padding(24)
      .onChange(of: model.images.map(\.id)) { _, _ in
        if removed, image == nil { model.goBack() }
      }
  }
  private func imageSize(_ title: String, _ bytes: Double?) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(bytesText(bytes)).monospacedDigit()
    }
  }
}
