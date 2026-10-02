import ColimaAppState
import ColimaCore
import SwiftUI

// Values are read when the tab opens and dropped when it closes. Sensitive
// ones stay masked until revealed one at a time, and copying needs a reveal.
struct EnvironmentPanel: View {
  @ObservedObject var model: Dashboard
  let containerID: String
  @State private var variables: [EnvironmentVariable]?
  @State private var error: String?
  @State private var revealed: Set<String> = []
  @State private var search = ""
  private var visible: [EnvironmentVariable] {
    (variables ?? []).filter {
      search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        TextField("Filter variables", text: $search).textFieldStyle(.roundedBorder)
          .frame(maxWidth: 320)
        Spacer()
        if let variables {
          let hidden = variables.filter(\.sensitive).count
          Text(
            hidden == 0
              ? countText(variables.count, "variable")
              : "\(countText(variables.count, "variable")) · \(hidden) masked"
          ).font(.caption).foregroundStyle(.secondary)
        }
        if !revealed.isEmpty { Button("Hide all") { revealed.removeAll() } }
      }
      if let error { StatusMessage(text: error) }
      if variables == nil && error == nil { ProgressView().controlSize(.small) }
      if let variables, variables.isEmpty {
        Text("This container has no environment variables.").foregroundStyle(.secondary)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(visible) { variable in
            row(variable)
            Divider()
          }
        }
      }
      Text(
        "Names that usually hold credentials, and URLs with a password, are masked. Values are read only while this tab is open."
      ).font(.caption).foregroundStyle(.secondary)
    }
    .task(id: containerID) {
      variables = nil
      revealed = []
      error = nil
      do { variables = try await model.backend.environment(containerID) } catch {
        self.error = "Could not read the environment: " + error.localizedDescription
      }
    }
    .onDisappear {
      variables = nil
      revealed = []
    }
  }

  private func row(_ variable: EnvironmentVariable) -> some View {
    let masked = variable.sensitive && !revealed.contains(variable.name)
    return HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(variable.name).font(.system(.callout, design: .monospaced).weight(.medium))
        .frame(width: 240, alignment: .leading).lineLimit(1).truncationMode(.middle)
        .help(variable.name)
      Group {
        if masked {
          Text("••••••••").foregroundStyle(.secondary)
        } else {
          Text(variable.value.isEmpty ? "(empty)" : variable.value)
            .foregroundStyle(variable.value.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
        }
      }.font(.system(.callout, design: .monospaced)).lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
      if variable.sensitive {
        Button {
          if masked { revealed.insert(variable.name) } else { revealed.remove(variable.name) }
        } label: {
          Image(systemName: masked ? "eye" : "eye.slash")
        }.buttonStyle(.borderless).help(masked ? "Reveal value" : "Hide value")
          .accessibilityLabel(masked ? "Reveal \(variable.name)" : "Hide \(variable.name)")
      }
      Button {
        Launcher.copy(variable.value)
      } label: {
        Image(systemName: "doc.on.doc")
      }.buttonStyle(.borderless).disabled(masked)
        .help(masked ? "Reveal the value to copy it" : "Copy value")
    }.padding(.vertical, 7)
  }
}
