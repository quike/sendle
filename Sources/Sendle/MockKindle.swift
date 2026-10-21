import AppKit
import Foundation
import PDFKit
import SendleKindleUSB

/// The files of a Kindle as snapshot mode mounts it, laid out for the fixture library's books:
/// Sendle's own copies, a copy of another edition, a calibre book, downloads, a PDF and notes.
enum MockKindle {
  private struct Book {
    let path: String
    let date: String
    let contents: Contents
  }

  private enum Contents {
    case azw3(
      title: String, author: String, asin: String, thumbnail: Bool,
      extra: [(UInt32, String)] = [])
    case other(String)
    case pdf(title: String)
  }

  /// Replaces whatever is at `root` with the Kindle's folders and books.
  static func write(to root: URL) throws {
    let files = FileManager.default
    try? files.removeItem(at: root)
    let thumbnails = root.appending(path: "system/thumbnails", directoryHint: .isDirectory)
    try files.createDirectory(at: thumbnails, withIntermediateDirectories: true)
    try files.createDirectory(
      at: root.appending(path: "documents", directoryHint: .isDirectory),
      withIntermediateDirectories: true)
    try Data("[]".utf8).write(to: root.appending(path: "metadata.calibre"))
    for book in books {
      let url = root.appending(path: "documents").appending(path: book.path)
      try files.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try write(book.contents, to: url, thumbnails: thumbnails)
      try files.setAttributes([.modificationDate: date(book.date)], ofItemAtPath: url.path)
    }
    try writeStoreSidecar(root: root)
    try writeSkippedFiles(root: root)
  }

  private static let books: [Book] = [
    Book(
      path: "Alice's Adventures in Wonderland - Lewis Carroll.azw3", date: "2026-10-16T09:30:00Z",
      contents: .azw3(
        title: "Alice's Adventures in Wonderland", author: "Lewis Carroll",
        asin: AZW3Metadata.asin(for: "Alice's Adventures in Wonderland - Lewis Carroll"),
        thumbnail: true, extra: [(524, "en"), (106, "1865")])),
    Book(
      path: "Dracula - Bram Stoker.azw3", date: "2026-10-15T18:05:00Z",
      contents: .azw3(
        title: "Dracula", author: "Bram Stoker",
        asin: AZW3Metadata.asin(for: "Dracula - Bram Stoker"), thumbnail: true)),
    Book(
      path: "Frankenstein - Mary Shelley (2).azw3", date: "2026-10-14T11:20:00Z",
      contents: .azw3(
        title: "Frankenstein", author: "Mary Shelley",
        asin: AZW3Metadata.asin(for: "edition:urn:uuid:other#2"), thumbnail: true)),
    Book(
      path: "Abreu, Andrea/Panza de burro - Andrea Abreu.azw3", date: "2026-09-30T08:00:00Z",
      contents: .azw3(
        title: "Panza de burro", author: "Andrea Abreu",
        asin: "9f1c3e52-6a7b-4d1e-8c2a-5b0f7d4e1a36", thumbnail: false)),
    Book(
      path:
        "Downloads/Items01/Pride and Prejudice - Jane Austen_OLE6OR2WWT5NC3Z6D6AXPK74XXPLQZ2V.kfx",
      date: "2026-10-12T20:45:00Z", contents: .other("mock kfx")),
    Book(
      path: "Downloads/Items01/Bleak House_0123456789ABCDEF0123456789ABCDEF.kfx",
      date: "2026-10-12T19:10:00Z", contents: .other("mock kfx")),
    Book(
      path: "Downloads/Items01/The Hobbit_B007978NPG.kfx", date: "2026-08-21T07:15:00Z",
      contents: .other("mock kfx")),
    Book(path: "1984.pdf", date: "2026-10-03T13:00:00Z", contents: .pdf(title: "1984")),
    Book(
      path: "Beowulf.txt", date: "2026-08-02T10:00:00Z", contents: .other("Beowulf")),
    Book(path: "My notes.txt", date: "2026-07-09T16:30:00Z", contents: .other("Notes")),
  ]

  private static func write(_ contents: Contents, to url: URL, thumbnails: URL) throws {
    switch contents {
    case .azw3(let title, let author, let asin, let thumbnail, let extra):
      let cover = cover(title: title)
      try MOBIBuilder.book(
        fullName: url.deletingPathExtension().lastPathComponent,
        exth: [(100, author), (113, asin), (501, "EBOK"), (503, title)] + extra, cover: cover
      ).write(to: url)
      if thumbnail, let cover {
        try cover.write(to: thumbnails.appending(path: "thumbnail_\(asin)_EBOK_portrait.jpg"))
      }
    case .other(let text):
      try Data(text.utf8).write(to: url)
    case .pdf(let title):
      let document = PDFDocument()
      if let data = cover(title: title), let image = NSImage(data: data),
        let page = PDFPage(image: image)
      {
        document.insert(page, at: 0)
      }
      document.documentAttributes = [PDFDocumentAttribute.titleAttribute: title]
      guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
    }
  }

  /// A store book is protected by its voucher.
  private static func writeStoreSidecar(root: URL) throws {
    let assets = root.appending(
      path: "documents/Downloads/Items01/The Hobbit_B007978NPG.sdr/assets",
      directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    try Data("voucher".utf8).write(to: assets.appending(path: "voucher"))
  }

  /// The files a listing leaves out.
  private static func writeSkippedFiles(root: URL) throws {
    let documents = root.appending(path: "documents")
    try Data("- clipping".utf8).write(to: documents.appending(path: "My Clippings.txt"))
    try Data(count: 4096).write(to: documents.appending(path: "._Dracula - Bram Stoker.azw3"))
  }

  private static func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? .distantPast
  }

  private static let palette: [(NSColor, NSColor)] = [
    (
      NSColor(srgbRed: 0.12, green: 0.23, blue: 0.37, alpha: 1),
      NSColor(srgbRed: 0.06, green: 0.13, blue: 0.22, alpha: 1)
    ),
    (
      NSColor(srgbRed: 0.48, green: 0.18, blue: 0.23, alpha: 1),
      NSColor(srgbRed: 0.24, green: 0.08, blue: 0.13, alpha: 1)
    ),
    (
      NSColor(srgbRed: 0.18, green: 0.36, blue: 0.31, alpha: 1),
      NSColor(srgbRed: 0.07, green: 0.19, blue: 0.16, alpha: 1)
    ),
    (
      NSColor(srgbRed: 0.29, green: 0.23, blue: 0.48, alpha: 1),
      NSColor(srgbRed: 0.13, green: 0.09, blue: 0.24, alpha: 1)
    ),
  ]

  /// A 300 × 450 JPEG with the title over a gradient.
  private static func cover(title: String) -> Data? {
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 450, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    let (top, bottom) = palette[
      title.unicodeScalars.reduce(0) { $0 + Int($1.value) } % palette.count]
    NSGradient(starting: top, ending: bottom)?.draw(
      in: NSRect(x: 0, y: 0, width: 300, height: 450), angle: -90)
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    NSString(string: title).draw(
      in: NSRect(x: 24, y: 150, width: 252, height: 160),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: NSColor.white,
        .paragraphStyle: style,
      ])
    return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
  }
}
