import Foundation
import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct USBKindleLibraryTests {
  let tree = try! KindleTree()
  let log = FakeActivityLog()
  let alice = "Alice's Adventures in Wonderland - Lewis Carroll"

  func library(device: String = "TEST-UUID", free: Int64? = 3_100_000_000) -> USBKindleLibrary {
    USBKindleLibrary(
      cacheDirectory: tree.cache, deviceKey: { _ in device }, freeSpace: { _ in free }, log: log)
  }

  @Test func listsEveryBookUnderDocuments() async throws {
    try tree.write(
      "\(alice).azw3",
      MOBIBuilder.book(exth: [
        (503, "Alice's Adventures in Wonderland"), (100, "Lewis Carroll"),
        (113, AZW3Metadata.asin(for: alice)), (501, "EBOK"),
      ]))
    try tree.write(
      "Abreu, Andrea/Panza de burro - Andrea Abreu.azw3",
      MOBIBuilder.book(exth: [
        (503, "Panza de burro"), (100, "Andrea Abreu"),
        (113, "0231b0ed-1c4e-4f3b-9a6e-2d5c7f1e8a90"),
      ]))
    try tree.writeRoot("metadata.calibre", "[]")
    let pride =
      "Downloads/Items01/Pride and Prejudice - Jane Austen_OLE6OR2WWT5NC3Z6D6AXPK74XXPLQZ2V.kfx"
    try tree.write(pride, "kfx")
    try tree.write("notes.txt", "hello")
    for skipped in [
      "My Clippings.txt", "._\(alice).azw3", ".sendle-1.partial", "\(alice).sdr/x.azw3",
      "cover.jpg",
    ] {
      try tree.write(skipped, "x")
    }
    let books = try await library().listing(of: tree.volume, progress: { _, _ in }).books
    #expect(
      books.map(\.id.relativePath).sorted() == [
        "Abreu, Andrea/Panza de burro - Andrea Abreu.azw3", "\(alice).azw3", pride, "notes.txt",
      ])
    let byPath = Dictionary(uniqueKeysWithValues: books.map { ($0.id.relativePath, $0) })
    #expect(byPath["\(alice).azw3"]?.source == .sendle)
    #expect(byPath["\(alice).azw3"]?.asinFollowsFileName == true)
    #expect(byPath["Abreu, Andrea/Panza de burro - Andrea Abreu.azw3"]?.source == .calibre)
    let email = byPath[pride]
    #expect(email?.source == .email)
    #expect(email?.authors == ["Jane Austen"])
    #expect(email?.documentType == "PDOC")
    #expect(byPath["notes.txt"]?.title == "notes")
    #expect(byPath["notes.txt"]?.source == .byHand)
  }

  @Test func aStoreKFXIsProtectedByItsVoucher() async throws {
    try tree.write("Downloads/Items01/The Hobbit_B007978NPG.kfx", "\u{EA}DRMION\u{EE}")
    try tree.write("Downloads/Items01/The Hobbit_B007978NPG.sdr/assets/voucher", "v")
    let hobbit = try await library().listing(of: tree.volume, progress: { _, _ in }).books.first
    #expect(hobbit?.isProtected == true)
    #expect(hobbit?.source == .amazon)
    #expect(hobbit?.asin == "B007978NPG")
    #expect(hobbit?.title == "The Hobbit")
  }

  @Test func aKFXWithTheDRMIONMagicIsProtected() async throws {
    var magic = Data([0xEA]) + Data("DRMION".utf8) + Data([0xEE])
    magic.append(Data(count: 16))
    try tree.write("Downloads/Items01/Dune_B00B7NPRY8.kfx", magic)
    try tree.write("Downloads/Items01/Emma_B00ABCDEFG.kfx", "plain")
    let books = try await library().listing(of: tree.volume, progress: { _, _ in }).books
    #expect(
      Dictionary(uniqueKeysWithValues: books.map { ($0.title, $0.isProtected) }) == [
        "Dune": true, "Emma": false,
      ])
  }

  @Test func aPDFShowsItsTitleOrItsFileName() async throws {
    try tree.write("orwell.pdf", makePDF(title: "Nineteen Eighty-Four", author: "George Orwell"))
    try tree.write("1984.pdf", makePDF(title: nil, author: nil))
    let books = try await library().listing(of: tree.volume, progress: { _, _ in }).books
    #expect(Set(books.map(\.title)) == ["Nineteen Eighty-Four", "1984"])
    #expect(books.first { $0.title == "Nineteen Eighty-Four" }?.authors == ["George Orwell"])
  }

  @Test func aDamagedBookIsListedByItsFileName() async throws {
    try tree.write(
      "Moby-Dick - Herman Melville.azw3", MOBIBuilder.book(exth: [(503, "X")]).prefix(120))
    let moby = try await library().listing(of: tree.volume, progress: { _, _ in }).books.first
    #expect(moby?.title == "Moby-Dick")
    #expect(moby?.authors == ["Herman Melville"])
  }

  @Test func aBookFillsWhatItLacksFromItsFileName() async throws {
    try tree.write(
      "Moby-Dick - Herman Melville.azw3", MOBIBuilder.book(exth: [(113, "SN5T2DYX77")]))
    let moby = try await library().listing(of: tree.volume, progress: { _, _ in }).books.first
    #expect(moby?.authors == ["Herman Melville"])
    #expect(moby?.asin == "SN5T2DYX77")
  }

  @Test(
    arguments: [
      ("2020-04-23T00:00:00+00:00", "2020"), ("1865", "1865"), ("April 2020", nil), ("20", nil),
      ("", nil),
    ] as [(String, String?)])
  func aPublishingDateGivesAYearOnlyWhenItStartsWithOne(
    published: String, year: String?
  ) async throws {
    try tree.write(
      "Book - Writer.azw3",
      MOBIBuilder.book(exth: [(503, "Book"), (100, "Writer"), (106, published)]))
    let listing = try await library().listing(of: tree.volume, progress: { _, _ in })
    #expect(listing.books.first?.year == year)
  }

  @Test func aBookShowsItsLanguage() async throws {
    try tree.write("Libro.azw3", MOBIBuilder.book(exth: [(503, "Book"), (524, "es")]))
    try tree.write("orwell.pdf", makePDF(title: "Nineteen Eighty-Four", author: nil))
    let books = try await library().listing(of: tree.volume, progress: { _, _ in }).books
    let byFormat = Dictionary(uniqueKeysWithValues: books.map { ($0.format, $0) })
    #expect(byFormat["azw3"]?.language == "es")
    #expect(byFormat["pdf"]?.language == nil)
    #expect(byFormat["pdf"]?.year == nil)
  }

  @Test func reportsProgressBookByBook() async throws {
    for name in ["a.txt", "b.txt", "c.txt"] { try tree.write(name, "x") }
    let steps = Recorder<[Int]>()
    _ = try await library().listing(of: tree.volume) { await steps.record([$0, $1]) }
    #expect(await steps.values == [[0, 3], [1, 3], [2, 3], [3, 3]])
  }

  @Test func aKindleUnpluggedMidListingSaysSo() async throws {
    for name in ["a.txt", "b.txt", "c.txt"] { try tree.write(name, "x") }
    let documents = tree.documents
    await #expect(throws: KindleListingError.deviceDisconnected) {
      _ = try await library().listing(of: tree.volume) { done, _ in
        if done == 1 { try? FileManager.default.removeItem(at: documents) }
      }
    }
  }

  @Test func aKindleWithoutDocumentsIsGone() async throws {
    try FileManager.default.removeItem(at: tree.documents)
    await #expect(throws: KindleListingError.deviceDisconnected) {
      _ = try await library().listing(of: tree.volume, progress: { _, _ in })
    }
  }

  @Test func aCancelledListingSaysSo() async throws {
    for name in ["a.txt", "b.txt"] { try tree.write(name, "x") }
    let library = library()
    let volume = tree.volume
    let started = Signal()
    let task = Task {
      await started.wait()
      return try await library.listing(of: volume, progress: { _, _ in })
    }
    task.cancel()
    await started.fire()
    await #expect(throws: KindleListingError.cancelled) { try await task.value }
  }

  @Test func saysHowMuchSpaceIsFree() async throws {
    #expect(
      try await library().listing(of: tree.volume, progress: { _, _ in }).freeBytes
        == 3_100_000_000)
  }

  @Test func logsWhatItRead() async throws {
    try tree.write("a.txt", "x")
    _ = try await library().listing(of: tree.volume, progress: { _, _ in })
    #expect(
      log.summary.last?.hasPrefix(
        "info USB Read Kindle (device TEST-UUID): 1 books, 1 read and 0 from the cache, in ")
        == true)
  }

  @Test func aFolderItCannotReadIsAnErrorNotAnEmptyShelf() async throws {
    try tree.write("Sub/a.txt", "x")
    try tree.write("b.txt", "x")
    let sub = tree.documents.appending(path: "Sub")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: sub.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sub.path)
    }
    await #expect(throws: KindleListingError.self) {
      _ = try await library().listing(of: tree.volume, progress: { _, _ in })
    }
    #expect(!FileManager.default.fileExists(atPath: tree.cacheFile("TEST-UUID").path))
  }

  @Test func aDocumentsFolderItCannotReadIsAnErrorNotAnEmptyShelf() async throws {
    try tree.write("a.txt", "x")
    let documents = tree.documents
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: documents.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: documents.path)
    }
    do {
      _ = try await library().listing(of: tree.volume, progress: { _, _ in })
      Issue.record("an unreadable Kindle listed as empty")
    } catch {
      guard case .unreadable = error else {
        Issue.record("expected .unreadable, got \(error)")
        return
      }
    }
  }

  @Test func listingLeavesTheKindleAsItWas() async throws {
    try tree.write("a.azw3", MOBIBuilder.book(exth: [(503, "A"), (113, "SN5T2DYX77")]))
    try tree.write("b.pdf", makePDF(title: "B", author: nil))
    try tree.write("Downloads/Items01/C_B007978NPG.kfx", "kfx")
    try tree.write("Downloads/Items01/C_B007978NPG.sdr/assets/voucher", "v")
    try tree.write("notes.txt", "x")
    try tree.writeRoot("system/thumbnails/thumbnail_SN5T2DYX77_EBOK_portrait.jpg", "jpg")
    let before = try snapshot()
    let library = library()
    _ = try await library.listing(of: tree.volume, progress: { _, _ in })
    _ = try await library.listing(of: tree.volume, progress: { _, _ in })
    #expect(try snapshot() == before)
    #expect(!(try snapshot().keys.contains { $0.contains("._") }))
  }

  /// Each entry's path with its size and date, so a new, removed or touched file shows.
  private func snapshot() throws -> [String: String] {
    var result: [String: String] = [:]
    for path in try FileManager.default.subpathsOfDirectory(atPath: tree.root.path) {
      let attributes = try FileManager.default.attributesOfItem(
        atPath: tree.root.appending(path: path).path)
      let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
      let date = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
      result[path] = "\(size) \(date)"
    }
    return result
  }
}
