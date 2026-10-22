#!/usr/bin/swift
// Writes a Books-style library of public-domain books with drawn covers, for snapshot mode and the
// README's screenshots: `BKLibrary-1-1.sqlite` and the books it lists, unzipped EPUBs and PDFs, as
// Books keeps them. Books stores absolute paths, so the library is written where it will be read.
// The IDs are the ones Sources/Sendle/Snapshot.swift and MockKindle.swift refer to.
// Usage: scripts/make-fixture-library.swift [folder]   (default: build/fixture-library)
//        SENDLE_LIBRARY_DB=<folder>/BKLibrary-1-1.sqlite then reads it.
import AppKit
import PDFKit
import SQLite3

struct FixtureBook {
  let id: String
  let title: String
  let author: String?
  var sortTitle: String? = nil
  var sortAuthor: String? = nil
  var isPDF = false
  var language = "en"
}

let books: [FixtureBook] = [
  FixtureBook(id: "A000", title: "Alice's Adventures in Wonderland", author: "Lewis Carroll"),
  FixtureBook(id: "A001", title: "Anna Karenina", author: "Leo Tolstoy"),
  FixtureBook(
    id: "A002", title: "Bleak House", author: "Charles Dickens", sortAuthor: "Dickens, Charles"),
  FixtureBook(id: "A003", title: "Candide", author: "Voltaire"),
  FixtureBook(id: "A004", title: "Crime and Punishment", author: "Fyodor Dostoevsky", isPDF: true),
  FixtureBook(id: "A005", title: "Don Quixote", author: "Miguel de Cervantes"),
  FixtureBook(id: "A006", title: "Dracula", author: "Bram Stoker"),
  FixtureBook(id: "A007", title: "Emma", author: "Jane Austen", sortAuthor: "Austen, Jane"),
  FixtureBook(
    id: "A008", title: "Fortunata y Jacinta", author: "Benito Pérez Galdós", language: "es"),
  FixtureBook(
    id: "A009", title: "Frankenstein", author: "Mary Shelley", sortAuthor: "Shelley, Mary"),
  FixtureBook(
    id: "A010", title: "Great Expectations", author: "Charles Dickens",
    sortAuthor: "Dickens, Charles"),
  FixtureBook(id: "A011", title: "Hamlet", author: "William Shakespeare"),
  FixtureBook(
    id: "A012", title: "The Hound of the Baskervilles", author: "Arthur Conan Doyle",
    sortTitle: "Hound of the Baskervilles, The", sortAuthor: "Doyle, Arthur Conan"),
  FixtureBook(id: "A013", title: "Jane Eyre", author: "Charlotte Brontë", isPDF: true),
  FixtureBook(id: "A014", title: "Kidnapped", author: "Robert Louis Stevenson"),
  FixtureBook(id: "A015", title: "Little Women", author: "Louisa May Alcott"),
  FixtureBook(id: "A016", title: "Middlemarch", author: "George Eliot"),
  FixtureBook(id: "A017", title: "Moby-Dick", author: "Herman Melville"),
  FixtureBook(id: "A018", title: "Nostromo", author: "Joseph Conrad"),
  FixtureBook(
    id: "A019", title: "Ñandú y otros cuentos", author: "Horacio Quiroga", language: "es"),
  FixtureBook(
    id: "A020", title: "Oliver Twist", author: "Charles Dickens", sortAuthor: "Dickens, Charles"),
  FixtureBook(
    id: "A021", title: "Persuasion", author: "Jane Austen", sortAuthor: "Austen, Jane"),
  FixtureBook(
    id: "A022", title: "Pride and Prejudice", author: "Jane Austen", sortAuthor: "Austen, Jane",
    isPDF: true),
  FixtureBook(id: "A023", title: "Robinson Crusoe", author: "Daniel Defoe"),
  FixtureBook(
    id: "A024", title: "Sense and Sensibility", author: "Jane Austen",
    sortAuthor: "Austen, Jane"),
  FixtureBook(
    id: "A025", title: "¡Viva mi dueño!", author: "Ramón del Valle-Inclán", language: "es"),
  FixtureBook(
    id: "A026", title: "The Time Machine", author: "H. G. Wells", sortTitle: "Time Machine, The"),
  FixtureBook(id: "A027", title: "Ulysses", author: "James Joyce"),
  FixtureBook(id: "A028", title: "Vanity Fair", author: "William Makepeace Thackeray"),
  FixtureBook(id: "A029", title: "War and Peace", author: "Leo Tolstoy"),
  FixtureBook(id: "A030", title: "Wuthering Heights", author: "Emily Brontë"),
  FixtureBook(
    id: "A031", title: "20,000 Leagues Under the Sea", author: "Jules Verne", isPDF: true),
  FixtureBook(id: "A032", title: "Émile", author: "Jean-Jacques Rousseau"),
  FixtureBook(id: "A033", title: "Treasure Island", author: "Robert Louis Stevenson"),
  FixtureBook(id: "A034", title: "Walden", author: "Henry David Thoreau"),
  FixtureBook(id: "A035", title: "Beowulf", author: nil),
]

/// Newest first: the books the panel opens on, sorted by date added, with the ones snapshot mode
/// selects in the first rows.
let addedOrder = [
  "A006", "A022", "A000", "A017", "A004", "A013", "A020", "A009", "A026", "A010", "A033", "A034",
  "A035", "A032", "A031", "A030", "A029", "A028", "A027", "A025", "A024", "A023", "A021", "A019",
  "A018", "A016", "A015", "A014", "A012", "A011", "A008", "A007", "A005", "A003", "A002", "A001",
]

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
  exit(2)
}

// MARK: Covers

/// Cloth colours; each title always gets the same one. MockKindle.swift draws its covers alike.
let palette: [(Int, Int, Int)] = [
  (0x1F, 0x3A, 0x5F), (0x7A, 0x2E, 0x3A), (0x2E, 0x5B, 0x4F), (0x4A, 0x3A, 0x7A),
  (0x9A, 0x6A, 0x26), (0x3F, 0x4A, 0x55), (0x1F, 0x5E, 0x66), (0x6B, 0x24, 0x40),
]
let ink = NSColor(srgbRed: 0.96, green: 0.92, blue: 0.85, alpha: 1)

func serif(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
  let font = NSFont.systemFont(ofSize: size, weight: weight)
  return font.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) }
    ?? font
}

/// The largest size up to `size` at which `text` fits in `box`.
func fitted(_ text: String, size: CGFloat, weight: NSFont.Weight, in box: CGSize)
  -> [NSAttributedString.Key: Any]
{
  let style = NSMutableParagraphStyle()
  style.alignment = .center
  style.lineBreakMode = .byWordWrapping
  var size = size
  while true {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: serif(size, weight), .foregroundColor: ink, .paragraphStyle: style,
    ]
    let needed = NSString(string: text).boundingRect(
      with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin], attributes: attributes)
    let longestWord =
      text.split(separator: " ").map {
        NSString(string: String($0)).size(withAttributes: attributes).width
      }.max() ?? 0
    if (needed.height <= box.height && longestWord <= box.width) || size <= 12 {
      return attributes
    }
    size -= 2
  }
}

/// A 600 × 900 JPEG: a cloth-coloured board with a darker hinge, a double frame, the title in the
/// middle and the author near the foot.
func cover(title: String, author: String?) -> Data {
  let width = 600.0
  let height = 900.0
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else { fail("Can't draw a cover") }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  let fnv = title.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
  let (red, green, blue) = palette[Int(fnv % UInt32(palette.count))]
  let cloth = NSColor(
    srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
  let board = NSRect(x: 0, y: 0, width: width, height: height)
  NSGradient(
    starting: cloth.blended(withFraction: 0.12, of: .white) ?? cloth,
    ending: cloth.blended(withFraction: 0.35, of: .black) ?? cloth)?.draw(in: board, angle: -90)
  NSGradient(
    starting: NSColor(white: 0, alpha: 0.35), ending: NSColor(white: 0, alpha: 0))?.draw(
      in: NSRect(x: 0, y: 0, width: 34, height: height), angle: 0)

  for (inset, alpha, line) in [(40.0, 0.55, 3.0), (52.0, 0.3, 1.5)] {
    ink.withAlphaComponent(alpha).setStroke()
    let frame = NSBezierPath(rect: board.insetBy(dx: inset, dy: inset).offsetBy(dx: 8, dy: 0))
    frame.lineWidth = line
    frame.stroke()
  }

  let titleBox = NSRect(x: 110, y: 360, width: 396, height: 330)
  let titleAttributes = fitted(title, size: 64, weight: .bold, in: titleBox.size)
  let titleHeight = NSString(string: title).boundingRect(
    with: CGSize(width: titleBox.width, height: .greatestFiniteMagnitude),
    options: [.usesLineFragmentOrigin], attributes: titleAttributes
  ).height
  let titleTop = titleBox.midY + titleHeight / 2
  NSString(string: title).draw(
    with: NSRect(
      x: titleBox.minX, y: titleTop - titleHeight, width: titleBox.width,
      height: titleHeight),
    options: [.usesLineFragmentOrigin], attributes: titleAttributes)

  ink.withAlphaComponent(0.6).setFill()
  NSRect(x: width / 2 + 8 - 36, y: titleTop - titleHeight - 44, width: 72, height: 2).fill()

  if let author {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    NSString(string: author.uppercased()).draw(
      in: NSRect(x: 100, y: 120, width: 416, height: 80),
      withAttributes: [
        .font: serif(26, .medium), .foregroundColor: ink.withAlphaComponent(0.85),
        .paragraphStyle: style, .kern: 3,
      ])
  }
  NSGraphicsContext.restoreGraphicsState()
  guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
  else { fail("Can't encode a cover") }
  return jpeg
}

// MARK: Books

func xml(_ text: String) -> String {
  text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}

/// An unzipped EPUB 3, as Books keeps one. It names no identifier, so Sendle matches it on the
/// Kindle by title and author, as MockKindle's copies expect.
func writeEPUB(_ book: FixtureBook, to root: URL) throws {
  let oebps = root.appending(path: "OEBPS", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(
    at: root.appending(path: "META-INF"), withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)
  try Data("application/epub+zip".utf8).write(to: root.appending(path: "mimetype"))
  try Data(
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """.utf8
  ).write(to: root.appending(path: "META-INF/container.xml"))
  let creator = book.author.map { "\n    <dc:creator>\(xml($0))</dc:creator>" } ?? ""
  try Data(
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>\(xml(book.title))</dc:title>\(creator)
        <dc:language>\(book.language)</dc:language>
        <meta name="cover" content="cover"/>
      </metadata>
      <manifest>
        <item id="cover" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="text" href="text.xhtml" media-type="application/xhtml+xml"/>
      </manifest>
      <spine>
        <itemref idref="text"/>
      </spine>
    </package>
    """.utf8
  ).write(to: oebps.appending(path: "content.opf"))
  try Data(
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
      <head><title>\(xml(book.title))</title></head>
      <body><nav epub:type="toc"><ol><li><a href="text.xhtml">\(xml(book.title))</a></li></ol></nav></body>
    </html>
    """.utf8
  ).write(to: oebps.appending(path: "nav.xhtml"))
  try Data(
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml">
      <head><title>\(xml(book.title))</title></head>
      <body><h1>\(xml(book.title))</h1><p>\(xml(book.author ?? "Anonymous"))</p></body>
    </html>
    """.utf8
  ).write(to: oebps.appending(path: "text.xhtml"))
  try cover(title: book.title, author: book.author).write(to: oebps.appending(path: "cover.jpg"))
}

/// One page, the cover, with the title and author in the document's info.
func writePDF(_ book: FixtureBook, to url: URL) throws {
  let document = PDFDocument()
  guard let image = NSImage(data: cover(title: book.title, author: book.author)),
    let page = PDFPage(image: image)
  else { fail("Can't make \(book.title)'s PDF") }
  document.insert(page, at: 0)
  var info: [PDFDocumentAttribute: Any] = [.titleAttribute: book.title]
  info[.authorAttribute] = book.author
  document.documentAttributes = info
  guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
}

// MARK: Database

func writeDatabase(_ rows: [(FixtureBook, URL)], to url: URL) {
  var db: OpaquePointer?
  guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { fail("Can't create \(url.path)") }
  defer { sqlite3_close(db) }
  let schema = """
    CREATE TABLE ZBKLIBRARYASSET (Z_PK INTEGER PRIMARY KEY, ZASSETID VARCHAR, ZTITLE VARCHAR,
      ZAUTHOR VARCHAR, ZPATH VARCHAR, ZLANGUAGE VARCHAR, ZSTOREID VARCHAR,
      ZCREATIONDATE TIMESTAMP, ZCONTENTTYPE INTEGER, ZISHIDDEN INTEGER, ZISSAMPLE INTEGER,
      ZSTATE INTEGER, ZFILESIZE INTEGER, ZSORTTITLE VARCHAR, ZSORTAUTHOR VARCHAR)
    """
  guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { fail("Can't create the table") }
  let insert = """
    INSERT INTO ZBKLIBRARYASSET (ZASSETID, ZTITLE, ZAUTHOR, ZPATH, ZLANGUAGE, ZCREATIONDATE,
      ZCONTENTTYPE, ZISHIDDEN, ZISSAMPLE, ZSTATE, ZFILESIZE, ZSORTTITLE, ZSORTAUTHOR)
    VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 1, ?, ?, ?)
    """
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, insert, -1, &statement, nil) == SQLITE_OK else {
    fail("Can't prepare the insert")
  }
  defer { sqlite3_finalize(statement) }
  let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  func bind(_ index: Int32, _ text: String?) {
    if let text {
      sqlite3_bind_text(statement, index, text, -1, transient)
    } else {
      sqlite3_bind_null(statement, index)
    }
  }
  // 2026-09-01, in seconds since 2001 as Core Data stores dates; a day between books.
  let newest = 809_913_600.0
  for (index, (book, path)) in rows.enumerated() {
    let rank = addedOrder.firstIndex(of: book.id) ?? addedOrder.count
    sqlite3_reset(statement)
    bind(1, book.id)
    bind(2, book.title)
    bind(3, book.author)
    bind(4, path.path)
    bind(5, book.language)
    sqlite3_bind_double(statement, 6, newest - Double(rank) * 86_400)
    sqlite3_bind_int64(statement, 7, book.isPDF ? 3 : 1)
    sqlite3_bind_int64(statement, 8, 1_200_000 + Int64(index) * 10_000)
    bind(9, book.sortTitle ?? book.title)
    bind(10, book.sortAuthor)
    guard sqlite3_step(statement) == SQLITE_DONE else { fail("Can't insert \(book.title)") }
  }
}

// MARK: Main

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count <= 1 else { fail("Usage: make-fixture-library.swift [folder]") }
let folder = URL(
  fileURLWithPath: arguments.first ?? "build/fixture-library", isDirectory: true
).standardizedFileURL
let shelf = folder.appending(path: "books", directoryHint: .isDirectory)
try? FileManager.default.removeItem(at: folder)
do {
  try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
  var rows: [(FixtureBook, URL)] = []
  for book in books {
    let file = shelf.appending(path: book.title + (book.isPDF ? ".pdf" : ".epub"))
    if book.isPDF {
      try writePDF(book, to: file)
    } else {
      try writeEPUB(book, to: file)
    }
    rows.append((book, file))
  }
  writeDatabase(rows, to: folder.appending(path: "BKLibrary-1-1.sqlite"))
} catch {
  fail("Couldn't write the library: \(error)")
}
print(folder.appending(path: "BKLibrary-1-1.sqlite").path)
