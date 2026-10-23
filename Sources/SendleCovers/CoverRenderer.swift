import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns cover sources into PNG thumbnails no larger than `maxPixel` on their longest side.
package enum CoverRenderer {
  package static func png(fromImageAt url: URL, maxPixel: Int) -> Data? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return png(image)
  }

  /// The first page, on white.
  package static func png(fromPDFAt url: URL, maxPixel: Int) -> Data? {
    guard let document = CGPDFDocument(url as CFURL), document.isUnlocked,
      let page = document.page(at: 1)
    else { return nil }
    let box = page.getBoxRect(.cropBox)
    let turned = page.rotationAngle % 180 != 0
    let size = turned ? CGSize(width: box.height, height: box.width) : box.size
    guard size.width > 0, size.height > 0 else { return nil }
    let scale = CGFloat(maxPixel) / max(size.width, size.height)
    let width = max(1, Int((size.width * scale).rounded()))
    let height = max(1, Int((size.height * scale).rounded()))
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale)
    context.concatenate(
      page.getDrawingTransform(
        .cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
    context.drawPDFPage(page)
    return context.makeImage().flatMap(png)
  }

  private static func png(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }
}
