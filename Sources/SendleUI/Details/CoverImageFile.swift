import Foundation
import ImageIO
import SendleDomain
import UniformTypeIdentifiers

/// An image file chosen or dropped as a book's cover, checked as saving it checks it.
struct CoverImageFile: Sendable {
  /// What saving scales and re-encodes.
  let data: Data
  /// A small copy for the sheet to draw, so a large image isn't decoded while it draws.
  let preview: Data

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
    guard data.count <= CoverChange.maxImageBytes else { return .failure(.imageTooLarge) }
    guard let preview = preview(of: data) else { return .failure(.unreadableImage) }
    return .success(CoverImageFile(data: data, preview: preview))
  }

  /// Nil when ImageIO, which saving decodes with, can't read the first image.
  private static func preview(of data: Data) -> Data? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: previewPixels,
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0,
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
