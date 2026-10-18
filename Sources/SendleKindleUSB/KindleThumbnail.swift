import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A Kindle's library doesn't draw a sideloaded book's cover from the book. It looks in
/// `system/thumbnails` for a picture named after the book's ASIN and type, and failing that asks
/// Amazon, which knows nothing of the book and answers "No image available".
enum KindleThumbnail {
  enum Outcome: Equatable {
    case written(String)
    case noSystemFolder
    case noCover
    case failed(String)
  }

  /// The height of the covers Calibre leaves there.
  static let maxPixelSize = 500

  /// Puts the cover of the AZW3 at `book` where the library of the Kindle at `root` looks for it.
  /// A book without a cover, or a Kindle without a `system` folder, is left as it is.
  @discardableResult
  static func write(for book: URL, onKindleAt root: URL) -> Outcome {
    let system = root.appending(path: "system", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: system.path) else { return .noSystemFolder }
    guard let data = try? Data(contentsOf: book), let metadata = AZW3Metadata(data),
      let cover = metadata.cover, let jpeg = jpeg(from: cover)
    else { return .noCover }
    let folder = system.appending(path: "thumbnails", directoryHint: .isDirectory)
    let name = "thumbnail_\(metadata.asin)_\(metadata.documentType)_portrait.jpg"
    let thumbnail = folder.appending(path: name)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try jpeg.write(to: thumbnail, options: .atomic)
      DeviceSync.flush(thumbnail)
      AppleDouble.remove(beside: thumbnail)
      DeviceSync.flush(folder)
      return .written(name)
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  /// `cover` as a JPEG no larger than `maxPixelSize` on its longer side.
  private static func jpeg(from cover: Data) -> Data? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    let data = NSMutableData()
    guard let source = CGImageSourceCreateWithData(cover as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
      let destination = CGImageDestinationCreateWithData(
        data, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(
      destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}
