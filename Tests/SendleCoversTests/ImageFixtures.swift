import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageFixtures {
  struct Failure: Error {}

  /// A solid red PNG of the given size.
  static func png(width: Int, height: Int) throws -> Data {
    try image(width: width, height: height, type: .png, properties: [:])
  }

  /// A solid red JPEG stored at the given size and tagged with an EXIF orientation.
  static func jpeg(width: Int, height: Int, orientation: Int) throws -> Data {
    try image(
      width: width, height: height, type: .jpeg,
      properties: [kCGImagePropertyOrientation: orientation])
  }

  private static func image(
    width: Int, height: Int, type: UTType, properties: [CFString: Any]
  ) throws -> Data {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Failure() }
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { throw Failure() }
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, type.identifier as CFString, 1, nil)
    else { throw Failure() }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw Failure() }
    return data as Data
  }

  /// A one-page PDF of the given size in points, filled black.
  static func writePDF(width: CGFloat, height: CGFloat, to url: URL) throws {
    var box = CGRect(x: 0, y: 0, width: width, height: height)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw Failure() }
    context.beginPDFPage(nil)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(box)
    context.endPDFPage()
    context.closePDF()
  }

  /// A one-page PDF of `width`×`height` points with `/Rotate rotation` and a 20-point black
  /// square in the page's top-left corner. Written by hand: CGContext can't set `/Rotate`.
  static func markedPDF(width: Int, height: Int, rotation: Int) -> Data {
    let content = "0 0 0 rg 0 \(height - 20) 20 20 re f"
    let objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(width) \(height)] /Rotate \(rotation)"
        + " /Contents 4 0 R >>",
      "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
    ]
    var pdf = "%PDF-1.4\n"
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
      offsets.append(pdf.utf8.count)
      pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
    }
    let xref = pdf.utf8.count
    pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets {
      pdf += String(format: "%010d 00000 n \n", offset)
    }
    pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
    return Data(pdf.utf8)
  }

  /// A one-page PDF that needs a password to open.
  static func writeLockedPDF(to url: URL) throws {
    var box = CGRect(x: 0, y: 0, width: 200, height: 300)
    let auxiliary =
      [kCGPDFContextUserPassword: "secret", kCGPDFContextOwnerPassword: "secret"] as CFDictionary
    guard let context = CGContext(url as CFURL, mediaBox: &box, auxiliary) else { throw Failure() }
    context.beginPDFPage(nil)
    context.endPDFPage()
    context.closePDF()
  }

  /// The 0–255 RGB colour of the pixel at (`x`, `y`), counted from the top-left corner.
  static func colour(of data: Data, x: Int, y: Int) -> [UInt8]? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB)
    else { return nil }
    var pixel = [UInt8](repeating: 0, count: 4)
    let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(
        image,
        in: CGRect(x: -x, y: y + 1 - image.height, width: image.width, height: image.height))
      return true
    }
    return drawn ? Array(pixel.prefix(3)) : nil
  }

  /// The pixel size of an encoded image.
  static func size(of data: Data) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return (image.width, image.height)
  }

  /// The colour of the image's centre pixel as 0–255 RGB.
  static func centreColour(of data: Data) -> [UInt8]? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB)
    else { return nil }
    var pixel = [UInt8](repeating: 0, count: 4)
    let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(
        image,
        in: CGRect(
          x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
          width: CGFloat(image.width), height: CGFloat(image.height)))
      return true
    }
    return drawn ? Array(pixel.prefix(3)) : nil
  }
}
