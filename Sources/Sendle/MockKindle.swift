import AppKit
import Foundation
import PDFKit
import SendleKindleUSB

/// The files of a Kindle as snapshot mode mounts it, laid out for the books of
/// `scripts/make-fixture-library.swift`: Sendle's own copies, a copy of another edition, a calibre
/// book, downloads, a PDF and notes.
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
    case pdf(title: String, author: String)
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
      path: "Unamuno, Miguel de/Abel Sánchez - Miguel de Unamuno.azw3",
      date: "2026-09-30T08:00:00Z",
      contents: .azw3(
        title: "Abel Sánchez", author: "Miguel de Unamuno",
        asin: "9f1c3e52-6a7b-4d1e-8c2a-5b0f7d4e1a36", thumbnail: false)),
    Book(
      path:
        "Downloads/Items01/Pride and Prejudice - Jane Austen_OLE6OR2WWT5NC3Z6D6AXPK74XXPLQZ2V.kfx",
      date: "2026-10-12T20:45:00Z", contents: .other("mock kfx")),
    Book(
      path: "Downloads/Items01/Bleak House_0123456789ABCDEF0123456789ABCDEF.kfx",
      date: "2026-10-12T19:10:00Z", contents: .other("mock kfx")),
    Book(
      path: "Downloads/Items01/The Hound of the Baskervilles_B0FIXTURE1.kfx",
      date: "2026-08-21T07:15:00Z", contents: .other("mock kfx")),
    Book(
      path: "20,000 Leagues Under the Sea.pdf", date: "2026-10-03T13:00:00Z",
      contents: .pdf(title: "20,000 Leagues Under the Sea", author: "Jules Verne")),
    Book(
      path: "Beowulf.txt", date: "2026-08-02T10:00:00Z", contents: .other("Beowulf")),
    Book(path: "My notes.txt", date: "2026-07-09T16:30:00Z", contents: .other("Notes")),
  ]

  private static func write(_ contents: Contents, to url: URL, thumbnails: URL) throws {
    switch contents {
    case .azw3(let title, let author, let asin, let thumbnail, let extra):
      let cover = cover(title: title, author: author)
      try MOBIBuilder.book(
        fullName: url.deletingPathExtension().lastPathComponent,
        exth: [(100, author), (113, asin), (501, "EBOK"), (503, title)] + extra, cover: cover
      ).write(to: url)
      if thumbnail, let cover {
        try cover.write(to: thumbnails.appending(path: "thumbnail_\(asin)_EBOK_portrait.jpg"))
      }
    case .other(let text):
      try Data(text.utf8).write(to: url)
    case .pdf(let title, let author):
      let document = PDFDocument()
      if let data = cover(title: title, author: author), let image = NSImage(data: data),
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
      path: "documents/Downloads/Items01/The Hound of the Baskervilles_B0FIXTURE1.sdr/assets",
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

  /// The fixture library's cloth colours, so a book looks the same on both sides.
  private static let palette: [(CGFloat, CGFloat, CGFloat)] = [
    (0x1F, 0x3A, 0x5F), (0x7A, 0x2E, 0x3A), (0x2E, 0x5B, 0x4F), (0x4A, 0x3A, 0x7A),
    (0x9A, 0x6A, 0x26), (0x3F, 0x4A, 0x55), (0x1F, 0x5E, 0x66), (0x6B, 0x24, 0x40),
  ]
  private static let ink = NSColor(srgbRed: 0.96, green: 0.92, blue: 0.85, alpha: 1)

  /// A 600 × 900 JPEG drawn as `scripts/make-fixture-library.swift` draws the library's covers.
  private static func cover(title: String, author: String) -> Data? {
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 900, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    let fnv = title.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
    let (red, green, blue) = palette[Int(fnv % UInt32(palette.count))]
    let cloth = NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    let board = NSRect(x: 0, y: 0, width: 600, height: 900)
    NSGradient(
      starting: cloth.blended(withFraction: 0.12, of: .white) ?? cloth,
      ending: cloth.blended(withFraction: 0.35, of: .black) ?? cloth)?.draw(in: board, angle: -90)
    NSGradient(starting: NSColor(white: 0, alpha: 0.35), ending: NSColor(white: 0, alpha: 0))?
      .draw(in: NSRect(x: 0, y: 0, width: 34, height: 900), angle: 0)
    for (inset, alpha, width) in [(40.0, 0.55, 3.0), (52.0, 0.3, 1.5)] {
      ink.withAlphaComponent(alpha).setStroke()
      let frame = NSBezierPath(rect: board.insetBy(dx: inset, dy: inset).offsetBy(dx: 8, dy: 0))
      frame.lineWidth = width
      frame.stroke()
    }
    let box = NSRect(x: 110, y: 360, width: 396, height: 330)
    let (attributes, height) = titleAttributes(title, in: box.size)
    let top = box.midY + height / 2
    NSString(string: title).draw(
      with: NSRect(x: box.minX, y: top - height, width: box.width, height: height),
      options: .usesLineFragmentOrigin, attributes: attributes)
    ink.withAlphaComponent(0.6).setFill()
    NSRect(x: 272, y: top - height - 44, width: 72, height: 2).fill()
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    NSString(string: author.uppercased()).draw(
      in: NSRect(x: 100, y: 120, width: 416, height: 80),
      withAttributes: [
        .font: serif(26, .medium), .foregroundColor: ink.withAlphaComponent(0.85),
        .paragraphStyle: style, .kern: 3,
      ])
    return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
  }

  /// The title's attributes at the largest size up to 64 that fits `box`, and its height there.
  private static func titleAttributes(_ title: String, in box: CGSize) -> (
    [NSAttributedString.Key: Any], CGFloat
  ) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    var size: CGFloat = 64
    while true {
      let attributes: [NSAttributedString.Key: Any] = [
        .font: serif(size, .bold), .foregroundColor: ink, .paragraphStyle: style,
      ]
      let height = NSString(string: title).boundingRect(
        with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
        options: .usesLineFragmentOrigin, attributes: attributes
      ).height
      let longestWord =
        title.split(separator: " ").map {
          NSString(string: String($0)).size(withAttributes: attributes).width
        }.max() ?? 0
      if (height <= box.height && longestWord <= box.width) || size <= 12 {
        return (attributes, height)
      }
      size -= 2
    }
  }

  private static func serif(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    return font.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) }
      ?? font
  }
}
