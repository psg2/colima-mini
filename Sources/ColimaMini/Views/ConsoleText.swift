import AppKit
import ColimaCore
import Combine
import Foundation
import SwiftUI

struct ConsoleText: View {
  let text: String
  var body: some View {
    GeometryReader { geometry in
      ScrollView([.horizontal, .vertical]) {
        Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
          .fixedSize(horizontal: true, vertical: true)
          .frame(
            minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
      }.background(Color(nsColor: .textBackgroundColor))
    }
  }
}
