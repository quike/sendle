import AppKit
import Foundation
import PDFKit
import SendleDomain
import UniformTypeIdentifiers

/// The cover of a book on a Kindle, read from the Kindle and never written to it.
package enum KindleCovers {
  /// The Kindle's own thumbnail comes first, since that is the cover its library shows.
  package static func cover(of book: KindleBook, onKindleAt root: URL, maxPixel: Int) -> Cover {
    if let thumbnail = thumbnail(of: book, onKindleAt: root),
      let png = KindleImages.scaled(thumbnail, maxPixel: maxPixel, as: .png)
    {
      return .image(png)
    }
    let file = root.appending(path: "documents").appending(path: book.id.relativePath)
    guard FileManager.default.fileExists(atPath: file.path) else { return .unreadable }
    let image: Data?
    switch book.format {
    case "pdf": image = firstPage(ofPDFAt: file, maxPixel: maxPixel)
    case "txt", "kfx": image = nil
    default: image = embeddedCover(ofMobiAt: file)
    }
    return image.flatMap { KindleImages.scaled($0, maxPixel: maxPixel, as: .png) }.map(Cover.image)
      ?? .none
  }

  private static func thumbnail(of book: KindleBook, onKindleAt root: URL) -> Data? {
    guard let asin = book.asin, let type = book.documentType else { return nil }
    return try? Data(
      contentsOf: root.appending(path: "system").appending(path: "thumbnails")
        .appending(path: "thumbnail_\(asin)_\(type)_portrait.jpg"))
  }

  private static func embeddedCover(ofMobiAt file: URL) -> Data? {
    guard let bytes = FileBytes(url: file), let range = MobiLayout(bytes)?.cover else { return nil }
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
