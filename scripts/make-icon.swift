#!/usr/bin/swift
// Makes Sendle's icons from scripts/AppIcon-source.png, an off-white tile with an orange open book
// drawn with a soft shadow on a white canvas. Everything outside the tile becomes transparent; the
// shadow is kept as a dark shadow with its own transparency.
// Usage: scripts/make-icon.swift <source.png> <output.icns>        the app icon, at every size
//        scripts/make-icon.swift --logo <source.png> <output.png>  the panel header's logo: the
//                                                                  tile alone, 128 px, no shadow
import AppKit

/// The tile in the source, in pixels from its top left: the edge just inside its rim, and its
/// corners, each a quarter of a superellipse that starts this far from the corner and bulges by
/// `cornerExponent` (2 would be a circle).
let tileInSource = CGRect(x: 94, y: 89, width: 1059.5, height: 1062.5)
let cornerInSource: CGFloat = 325
let cornerExponent: CGFloat = 2.5
/// The canvas behind the tile, which the source paints in place of transparency.
let canvasWhite = 254

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
  exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let isLogo = arguments.first == "--logo"
let paths = isLogo ? Array(arguments.dropFirst()) : arguments
guard paths.count == 2 else {
  fail("Usage: make-icon.swift [--logo] <source.png> <output.icns|output.png>")
}
guard let sourceData = try? Data(contentsOf: URL(fileURLWithPath: paths[0])),
  let source = NSBitmapImageRep(data: sourceData)?.cgImage
else { fail("Can't read \(paths[0])") }
let output = URL(fileURLWithPath: paths[1])

func context(_ width: Int, _ height: Int) -> CGContext {
  CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// The source's shadow on its own: black, with the opacity that, laid over the canvas, gives each
/// pixel's darkest channel. A tint would be noise wherever the shadow is faint.
func shadowLayer() -> CGImage {
  let width = source.width
  let height = source.height
  let layer = context(width, height)
  layer.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
  let rowBytes = layer.bytesPerRow
  let pixels = layer.data!.bindMemory(to: UInt8.self, capacity: rowBytes * height)
  for row in 0..<height {
    for offset in stride(from: row * rowBytes, to: row * rowBytes + width * 4, by: 4) {
      let darkest = min(Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
      let alpha = max(0, canvasWhite - darkest)
      for channel in 0..<3 { pixels[offset + channel] = 0 }
      pixels[offset + 3] = UInt8(alpha * 255 / canvasWhite)
    }
  }
  return layer.makeImage()!
}

/// Draws the source so that its tile fills `tile`, in a context whose origin is at the bottom left.
func drawSource(_ image: CGImage, in context: CGContext, tile: CGRect) {
  let scaleX = tile.width / tileInSource.width
  let scaleY = tile.height / tileInSource.height
  let sourceBottom = CGFloat(source.height) - tileInSource.maxY
  context.draw(
    image,
    in: CGRect(
      x: tile.minX - tileInSource.minX * scaleX, y: tile.minY - sourceBottom * scaleY,
      width: CGFloat(source.width) * scaleX, height: CGFloat(source.height) * scaleY))
}

func tilePath(_ tile: CGRect) -> CGPath {
  let extent = cornerInSource * tile.width / tileInSource.width
  let straight = CGSize(width: tile.width / 2 - extent, height: tile.height / 2 - extent)
  let steps = 360
  let path = CGMutablePath()
  for step in 0...steps {
    let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
    let (cosine, sine) = (cos(angle), sin(angle))
    let point = CGPoint(
      x: tile.midX + (cosine < 0 ? -1 : 1)
        * (straight.width + pow(abs(cosine), 2 / cornerExponent) * extent),
      y: tile.midY + (sine < 0 ? -1 : 1)
        * (straight.height + pow(abs(sine), 2 / cornerExponent) * extent))
    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
  }
  path.closeSubpath()
  return path
}

func png(_ image: CGImage) -> Data {
  NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

/// The tile alone, edge to edge.
func logo(_ pixels: Int) -> CGImage {
  let canvas = context(pixels, pixels)
  canvas.interpolationQuality = .high
  let tile = CGRect(x: 0, y: 0, width: pixels, height: pixels)
  canvas.addPath(tilePath(tile))
  canvas.clip()
  drawSource(source, in: canvas, tile: tile)
  return canvas.makeImage()!
}

/// The macOS icon grid: an 824 px tile centred on a 1024 px canvas, with the source's shadow.
func master() -> CGImage {
  let canvas = context(1024, 1024)
  canvas.interpolationQuality = .high
  let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
  drawSource(shadowLayer(), in: canvas, tile: tile)
  canvas.addPath(tilePath(tile))
  canvas.clip()
  drawSource(source, in: canvas, tile: tile)
  return canvas.makeImage()!
}

func scaled(_ image: CGImage, to pixels: Int) -> CGImage {
  let canvas = context(pixels, pixels)
  canvas.interpolationQuality = .high
  canvas.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
  return canvas.makeImage()!
}

if isLogo {
  try png(logo(128)).write(to: output)
  exit(0)
}

let icon = master()
let iconset = FileManager.default.temporaryDirectory
  .appendingPathComponent("Sendle-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for size in [16, 32, 128, 256, 512] {
  try png(scaled(icon, to: size)).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
  try png(scaled(icon, to: size * 2))
    .write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }
