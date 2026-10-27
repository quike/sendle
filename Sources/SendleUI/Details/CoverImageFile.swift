import Foundation
import ImageIO
import SendleDomain
import UniformTypeIdentifiers

/// An image file chosen or dropped as a book's cover, checked as saving it checks it.
package struct CoverImageFile: Equatable, Sendable {
  /// What saving scales and re-encodes.
  package let data: Data
  /// A small copy for the sheet to draw, so a large image isn't decoded while it draws.
  package let preview: Data
  /// The image's size as drawn, after its orientation.
  package let pixelWidth: Int
  package let pixelHeight: Int

  private static let previewPixels = 400

  /// Only files are read, so a URL dropped from a browser is never fetched.
  static func read(_ url: URL) -> Result<CoverImageFile, EditDetailsError> {
    guard url.isFileURL else { return .failure(.unreadableImage) }
    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      size > CoverChange.maxImageBytes
    {
      return .failure(.imageTooLarge)
    }
    guard let data = try? Data(contentsOf: url) else { return .failure(.unreadableImage) }
    return make(from: data)
  }

  /// Image bytes from anywhere, such as a found cover, checked as `read` checks a file.
  package static func make(from data: Data) -> Result<CoverImageFile, EditDetailsError> {
    guard data.count <= CoverChange.maxImageBytes else { return .failure(.imageTooLarge) }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0, let size = pixelSize(of: source),
      let preview = preview(of: source)
    else { return .failure(.unreadableImage) }
    return .success(
      CoverImageFile(data: data, preview: preview, pixelWidth: size.width, pixelHeight: size.height)
    )
  }

  /// EXIF orientations 5 to 8 turn the image a quarter, so width and height swap.
  private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    return (5...8).contains(orientation) ? (height, width) : (width, height)
  }

  /// Nil when ImageIO, which saving decodes with, can't read the first image.
  private static func preview(of source: CGImageSource) -> Data? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: previewPixels,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    let png = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        png as CFMutableData, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? png as Data : nil
  }
}
