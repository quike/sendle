// Draws the background of the disk image window (Sendle on the left, Applications on the right,
// an arrow between them) as a TIFF with 1x and 2x images.
// Usage: swift scripts/make-dmg-background.swift <output.tiff>   (scripts/release-mac.sh runs it)
import AppKit

guard CommandLine.arguments.count == 2 else {
  print("Usage: swift scripts/make-dmg-background.swift <output.tiff>")
  exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
// Must match the window and icon positions in scripts/dmg-settings.py.
let size = CGSize(width: 640, height: 400)
let appCenter = CGPoint(x: 170, y: 200)
let applicationsCenter = CGPoint(x: 470, y: 200)

func render(scale: CGFloat) -> NSBitmapImageRep {
  guard
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
      pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
  else { fatalError("Could not make the bitmap") }
  rep.size = size
  NSGraphicsContext.saveGraphicsState()
  let context = NSGraphicsContext(bitmapImageRep: rep)
  NSGraphicsContext.current = context
  guard let ctx = context?.cgContext else { fatalError("No graphics context") }
  // AppKit's origin is bottom-left; the layout above is written top-down.
  ctx.translateBy(x: 0, y: size.height)
  ctx.scaleBy(x: 1, y: -1)

  // Finder draws the icon labels in black on a background picture, even in dark mode,
  // so the window stays light: a pale paper tone.
  let space = CGColorSpaceCreateDeviceRGB()
  let paper = CGGradient(
    colorsSpace: space,
    colors: [
      NSColor(red: 0.94, green: 0.95, blue: 0.99, alpha: 1).cgColor,
      NSColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])
  if let paper {
    ctx.drawLinearGradient(paper, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
  }

  // A soft blue glow under the app, Sendle's accent colour.
  let glow = CGGradient(
    colorsSpace: space,
    colors: [
      NSColor(red: 0.24, green: 0.55, blue: 1.0, alpha: 0.24).cgColor,
      NSColor(red: 0.24, green: 0.55, blue: 1.0, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])
  if let glow {
    ctx.drawRadialGradient(
      glow, startCenter: appCenter, startRadius: 0, endCenter: appCenter, endRadius: 150,
      options: [])
  }

  // The arrow from the app to Applications.
  let from = CGPoint(x: appCenter.x + 78, y: appCenter.y)
  let to = CGPoint(x: applicationsCenter.x - 78, y: appCenter.y)
  ctx.setStrokeColor(NSColor(red: 0.16, green: 0.18, blue: 0.26, alpha: 0.45).cgColor)
  ctx.setLineWidth(3)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  ctx.setLineDash(phase: 0, lengths: [1, 9])
  ctx.move(to: from)
  ctx.addLine(to: CGPoint(x: to.x - 6, y: to.y))
  ctx.strokePath()
  ctx.setLineDash(phase: 0, lengths: [])
  ctx.move(to: CGPoint(x: to.x - 12, y: to.y - 10))
  ctx.addLine(to: to)
  ctx.addLine(to: CGPoint(x: to.x - 12, y: to.y + 10))
  ctx.strokePath()

  // The captions, drawn the right way up.
  ctx.saveGState()
  ctx.translateBy(x: 0, y: size.height)
  ctx.scaleBy(x: 1, y: -1)
  let style = NSMutableParagraphStyle()
  style.alignment = .center
  func line(_ text: String, font: NSFont, color: NSColor, y: CGFloat, height: CGFloat) {
    NSAttributedString(
      string: text,
      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]
    ).draw(in: CGRect(x: 0, y: y, width: size.width, height: height))
  }
  line(
    "Drag Sendle into Applications", font: .systemFont(ofSize: 15, weight: .semibold),
    color: NSColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 0.9), y: 84, height: 22)
  line(
    "Then open it from Applications and look for the book in the menu bar.",
    font: .systemFont(ofSize: 12), color: NSColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 0.5),
    y: 62, height: 18)
  // The app is not notarized (no Developer ID), so macOS stops its first launch once.
  line(
    "First launch: System Settings → Privacy & Security → Open Anyway.",
    font: .systemFont(ofSize: 12, weight: .medium),
    color: NSColor(red: 0.62, green: 0.36, blue: 0.08, alpha: 0.85), y: 40, height: 18)
  ctx.restoreGState()

  NSGraphicsContext.restoreGraphicsState()
  return rep
}

let image = NSImage(size: size)
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
guard let tiff = image.tiffRepresentation(using: .lzw, factor: 0) else {
  fatalError("Could not encode the TIFF")
}
try tiff.write(to: output)
print("✓ \(output.path)")
