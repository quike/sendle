import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageFixtures {
  struct Failure: Error {}

  /// A solid red PNG of the given size.
  static func png(width: Int, height: Int) throws -> Data {
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
        data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
    else { throw Failure() }
    CGImageDestinationAddImage(destination, image, nil)
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
