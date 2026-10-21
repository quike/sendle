import AppKit
import Foundation
import PDFKit
import SendleDomain
import UniformTypeIdentifiers

/// The cover of a book on a Kindle, read from the Kindle and never written to it.
package enum KindleCovers {
  /// A cover record larger than this is a damaged offset, not a picture.
  static let maxEmbeddedCover = 8 << 20

  /// The Kindle's own thumbnail comes first, since that is the cover its library shows. A book
  /// that can't be opened is `.unreadable`, one that opens without a cover is `.none`.
  package static func cover(of book: KindleBook, onKindleAt root: URL, maxPixel: Int) -> Cover {
    if Task.isCancelled { return .unreadable }
    if let thumbnail = thumbnail(of: book, onKindleAt: root),
      let png = KindleImages.scaled(thumbnail, maxPixel: maxPixel, as: .png)
    {
      return .image(png)
    }
    let file = root.appending(path: "documents").appending(path: book.id.relativePath)
    guard FileManager.default.fileExists(atPath: file.path) else { return .unreadable }
    let format = book.format
    if format == "txt" || format == "kfx" { return .none }
    guard let bytes = FileBytes(url: file), !Task.isCancelled else { return .unreadable }
    let image =
      format == "pdf" ? firstPage(ofPDFAt: file, maxPixel: maxPixel) : embeddedCover(in: bytes)
    return image.flatMap { KindleImages.scaled($0, maxPixel: maxPixel, as: .png) }.map(Cover.image)
      ?? .none
  }

  private static func thumbnail(of book: KindleBook, onKindleAt root: URL) -> Data? {
    guard let asin = book.asin, let type = book.documentType else { return nil }
    return try? Data(
      contentsOf: root.appending(path: ThumbnailName.folder)
        .appending(path: ThumbnailName.of(asin: asin, type: type)))
  }

  private static func embeddedCover(in bytes: FileBytes) -> Data? {
    guard let range = MobiLayout(bytes)?.cover, range.count <= maxEmbeddedCover else { return nil }
    return bytes.bytes(range).map { Data($0) }
  }

  private static func firstPage(ofPDFAt file: URL, maxPixel: Int) -> Data? {
    guard let page = PDFDocument(url: file)?.page(at: 0) else { return nil }
    let box = page.bounds(for: .mediaBox)
    guard box.width > 0, box.height > 0 else { return nil }
    let scale = CGFloat(maxPixel) / max(box.width, box.height)
    let size = CGSize(width: box.width * scale, height: box.height * scale)
    return page.thumbnail(of: size, for: .mediaBox).tiffRepresentation
  }
}
