import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A minimal KF8 book: a PalmDB with record 0 (PalmDOC, MOBI and EXTH headers), one text record
/// and, with a cover, one image record.
func makeAZW3(asin: String = "EBOK000000", type: String = "EBOK", cover: Data? = nil) -> Data {
  var exth: [(UInt32, Data)] = [(113, Data(asin.utf8)), (501, Data(type.utf8))]
  if cover != nil { exth.append((201, bigEndian(UInt32(0)))) }
  var entries = Data()
  for (kind, value) in exth {
    entries += bigEndian(kind) + bigEndian(UInt32(8 + value.count)) + value
  }
  let exthSection =
    Data("EXTH".utf8) + bigEndian(UInt32(12 + entries.count)) + bigEndian(UInt32(exth.count))
    + entries
  var mobi = Data(count: 0xE8)
  mobi.replaceSubrange(0..<4, with: Data("MOBI".utf8))
  mobi.replaceSubrange(4..<8, with: bigEndian(UInt32(0xE8)))
  // The first image record, at 0x6C from record 0's start.
  mobi.replaceSubrange(0x5C..<0x60, with: bigEndian(cover == nil ? UInt32.max : 2))
  let record0 = Data(count: 16) + mobi + exthSection + Data(count: 4)
  let records = [record0, Data("<html>text</html>".utf8)] + (cover.map { [$0] } ?? [])

  var file = Data(count: 78)
  file.replaceSubrange(0..<5, with: Data("Book\0".utf8))
  file.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
  file.replaceSubrange(76..<78, with: bigEndian(UInt16(records.count)))
  var offset = 78 + 8 * records.count + 2
  for (index, record) in records.enumerated() {
    file += bigEndian(UInt32(offset)) + bigEndian(UInt32(index * 2))
    offset += record.count
  }
  file += Data(count: 2)
  for record in records { file += record }
  return file
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

private func bigEndian<T: FixedWidthInteger>(_ value: T) -> Data {
  withUnsafeBytes(of: value.bigEndian) { Data($0) }
}
