import ColimaAppState
import ColimaCore
import SwiftUI

struct ImagesView: View {
  @ObservedObject var model: Dashboard
  var visible: [DockerImage] {
    model.images.filter {
      model.imageSearch.isEmpty
        || ($0.name + " " + $0.imageID).localizedCaseInsensitiveContains(model.imageSearch)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("Images").font(.system(.title, design: .rounded).weight(.semibold))
          Text("Image sizes and the containers that use them").font(.caption).foregroundStyle(
            .secondary)
        }
        Spacer()
        RefreshButton(busy: model.imagesLoading) { await model.loadImages() }
      }
      TextField("Filter images", text: $model.imageSearch).textFieldStyle(.roundedBorder)
      if let error = model.imagesError { StatusMessage(text: error) }
      if model.imagesLoading { ProgressView().controlSize(.small) }
      ScrollView {
        LazyVStack(spacing: 1) {
          ForEach(visible) { image in
            Button {
              model.openImage(image.id)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: "square.3.layers.3d").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                  Text(image.name).fontWeight(.medium)
                  Text(
                    image.referencesAvailable
                      ? countText(image.containerIDs.count, "container")
                      : "Container use unavailable"
                  )
                  .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(bytesText(image.sizeBytes)).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
              }.padding(12).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("image.row." + image.name)
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
  }
}
struct ImageDetailView: View {
  @ObservedObject var model: Dashboard
  let id: String
  var image: DockerImage? { model.images.first { $0.id == id } }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Button {
        model.goBack()
      } label: {
        Label("Back", systemImage: "chevron.left")
      }.buttonStyle(.plain).foregroundStyle(.secondary)
      if let image {
        Text(image.name).font(.system(.title, design: .rounded).weight(.semibold))
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
  }
  private func imageSize(_ title: String, _ bytes: Double?) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(bytesText(bytes)).monospacedDigit()
    }
  }
}
