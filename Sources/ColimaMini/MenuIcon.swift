import AppKit
import ColimaCore
import Combine
import Foundation
import SwiftUI

// The same long ears, muzzle and neck as the application logo, reduced to a
// template silhouette so macOS supplies the correct menu bar foreground color.
let llamaMenuIcon = llamaIcon(alpha: 1)
// A stopped VM keeps the silhouette at reduced opacity; template images keep alpha.
let llamaMenuIconDimmed = llamaIcon(alpha: 0.4)

private func llamaIcon(alpha: CGFloat) -> NSImage {
  let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { _ in
    NSColor.black.withAlphaComponent(alpha).setFill()
    let head = NSBezierPath()
    let points: [NSPoint] = [
      NSPoint(x: 4, y: 19), NSPoint(x: 5, y: 10), NSPoint(x: 7, y: 7),
      NSPoint(x: 7, y: 1), NSPoint(x: 10, y: 6), NSPoint(x: 12, y: 2),
      NSPoint(x: 12, y: 8), NSPoint(x: 16, y: 10), NSPoint(x: 18, y: 13),
      NSPoint(x: 17, y: 15), NSPoint(x: 14, y: 15), NSPoint(x: 12, y: 13),
      NSPoint(x: 13, y: 19),
    ]
    head.move(to: points[0])
    for point in points.dropFirst() { head.line(to: point) }
    head.close()
    head.fill()
    NSBezierPath(roundedRect: NSRect(x: 1, y: 15, width: 5, height: 4), xRadius: 0.5, yRadius: 0.5)
      .fill()
    return true
  }
  image.isTemplate = true
  return image
}
