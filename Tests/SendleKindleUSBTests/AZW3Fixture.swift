import CoreGraphics
import Foundation
import ImageIO
import SendleKindleUSB
import UniformTypeIdentifiers

/// A minimal KF8 book with an ASIN and a type, and a cover if given.
func makeAZW3(asin: String = "EBOK000000", type: String = "EBOK", cover: Data? = nil) -> Data {
  MOBIBuilder.book(exth: [(113, asin), (501, type)], cover: cover)
}

/// A solid JPEG of the given size.
func makeJPEG(width: Int, height: Int) -> Data {
  let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
  context?.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
  context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
  let data = NSMutableData()
  guard let image = context?.makeImage(),
    let destination = CGImageDestinationCreateWithData(
      data, UTType.jpeg.identifier as CFString, 1, nil)
  else { return Data() }
  CGImageDestinationAddImage(destination, image, nil)
  CGImageDestinationFinalize(destination)
  return data as Data
}

/// The width and height of an image file, or nil if it isn't one.
func pixelSize(of data: Data) -> CGSize? {
  guard let source = CGImageSourceCreateWithData(data as CFData, nil),
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
    let width = properties[kCGImagePropertyPixelWidth] as? Int,
    let height = properties[kCGImagePropertyPixelHeight] as? Int
  else { return nil }
  return CGSize(width: width, height: height)
}
