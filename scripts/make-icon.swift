#!/usr/bin/swift
// Draws Sendle's app icon, the panel's badge at full size: a white book on the brand gradient.
// Usage: scripts/make-icon.swift <output.icns>
import AppKit

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("Usage: make-icon.swift <output.icns>\n".utf8))
  exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

func color(_ hex: Int, alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
    blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func render(_ pixels: Int) -> Data {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let context = NSGraphicsContext.current!.cgContext
  context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

  // The macOS icon grid: an 824 pt tile centred on a 1024 pt canvas, with a soft shadow.
  let tile = CGPath(
    roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185,
    cornerHeight: 185, transform: nil)
  context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, alpha: 0.35))
  context.addPath(tile)
  context.setFillColor(color(0x3d8bff))
  context.fillPath()
  context.setShadow(offset: .zero, blur: 0, color: nil)

  // The brand gradient, #7c5cff at the top left to #3d8bff at the bottom right, and a glow.
  context.saveGState()
  context.addPath(tile)
  context.clip()
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let brand = CGGradient(
    colorsSpace: space, colors: [color(0x7c5cff), color(0x3d8bff)] as CFArray, locations: [0, 1])!
  context.drawLinearGradient(
    brand, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
  let glow = CGGradient(
    colorsSpace: space, colors: [color(0xffffff, alpha: 0.28), color(0xffffff, alpha: 0)] as CFArray,
    locations: [0, 1])!
  context.drawRadialGradient(
    glow, startCenter: CGPoint(x: 512, y: 924), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 924), endRadius: 560, options: [])
  context.restoreGState()

  let configuration = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
  if let symbol = NSImage(systemSymbolName: "book.closed.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration)
  {
    let size = symbol.size
    let white = NSImage(size: size, flipped: false) { rect in
      symbol.draw(in: rect)
      NSColor.white.set()
      rect.fill(using: .sourceAtop)
      return true
    }
    context.setShadow(
      offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x1b1464, alpha: 0.45))
    white.draw(
      in: CGRect(
        x: 512 - size.width / 2, y: 512 - size.height / 2, width: size.width, height: size.height))
  }
  NSGraphicsContext.restoreGraphicsState()
  return bitmap.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory
  .appendingPathComponent("Sendle-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for size in [16, 32, 128, 256, 512] {
  try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
  try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
  FileHandle.standardError.write(Data("iconutil failed\n".utf8))
  exit(1)
}
