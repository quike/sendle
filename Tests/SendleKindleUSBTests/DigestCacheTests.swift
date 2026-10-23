import Foundation
import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DigestCacheTests {
  let tree: KindleTree

  init() throws {
    tree = try KindleTree()
  }

  func kindleDigester(_ digester: FakeFileDigester, device: String = "TEST-UUID")
    -> CachedKindleDigester
  {
    CachedKindleDigester(cacheDirectory: tree.cache, deviceKey: { _ in device }, digester: digester)
  }

  @Test func aKindleBookIsHashedOnceWhileItsSizeAndDateStayTheSame() async {
    let book = KindleBook.fixture(path: "scan.pdf", byteCount: 1_000)
    let digester = FakeFileDigester([book.url(on: tree.volume): "d1"])

    #expect(await kindleDigester(digester).sha256(of: book, on: tree.volume) == "d1")
    #expect(await kindleDigester(digester).sha256(of: book, on: tree.volume) == "d1")
    #expect(digester.requests.count == 1)

    let rewritten = KindleBook.fixture(
      path: "scan.pdf", byteCount: 1_000, modified: Date(timeIntervalSince1970: 1_800_000_000))
    let resized = KindleBook.fixture(path: "scan.pdf", byteCount: 2_000)
    _ = await kindleDigester(digester).sha256(of: rewritten, on: tree.volume)
    _ = await kindleDigester(digester).sha256(of: resized, on: tree.volume)
    #expect(digester.requests.count == 3)
  }

  @Test func eachKindleKeepsItsOwnDigests() async {
    let book = KindleBook.fixture(path: "scan.pdf")
    let digester = FakeFileDigester([book.url(on: tree.volume): "d1"])
    _ = await kindleDigester(digester, device: "A").sha256(of: book, on: tree.volume)
    _ = await kindleDigester(digester, device: "B").sha256(of: book, on: tree.volume)
    #expect(digester.requests.count == 2)
  }

  @Test func aKindleBookThatCannotBeReadIsAskedAgain() async {
    let book = KindleBook.fixture(path: "scan.pdf")
    let digester = FakeFileDigester()
    _ = await kindleDigester(digester).sha256(of: book, on: tree.volume)
    _ = await kindleDigester(digester).sha256(of: book, on: tree.volume)
    #expect(digester.requests.count == 2)
  }

  @Test func aFileOnTheMacIsHashedAgainOnlyOnceItChanges() async throws {
    let file = try makeTemporaryDirectory().appending(path: "book.pdf")
    try Data("one".utf8).write(to: file)
    let digester = FakeFileDigester([file: "d1"])
    let cached = CachedFileDigester(digester)

    #expect(await cached.sha256(of: file) == "d1")
    #expect(await cached.sha256(of: file) == "d1")
    #expect(digester.requests.count == 1)

    try Data("two".utf8).write(to: file)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)], ofItemAtPath: file.path)
    _ = await cached.sha256(of: file)
    #expect(digester.requests.count == 2)
  }

  @Test func aFileOnTheMacThatCannotBeReadIsAskedAgain() async throws {
    let file = try makeTemporaryDirectory().appending(path: "book.pdf")
    try Data("one".utf8).write(to: file)
    let digester = FakeFileDigester()
    let cached = CachedFileDigester(digester)
    _ = await cached.sha256(of: file)
    _ = await cached.sha256(of: file)
    #expect(digester.requests.count == 2)
  }

  @Test func aSecondMatchOfAnUnchangedKindleHashesNothing() async throws {
    let bytes = Data("%PDF-1.4 the same scan".utf8)
    try tree.write("scan.pdf", bytes)
    let onMac = try makeTemporaryDirectory().appending(path: "1984.pdf")
    try bytes.write(to: onMac)
    let pdf = Book.fixture(
      id: "orwell", title: "1984", format: .pdf, fileURL: onMac, sizeBytes: Int64(bytes.count))
    let library = USBKindleLibrary(
      cacheDirectory: tree.cache, deviceKey: { _ in "TEST-UUID" }, freeSpace: { _ in nil },
      log: FakeActivityLog())
    let digester = FakeFileDigester([
      onMac: "same", tree.documents.appending(path: "scan.pdf"): "same",
    ])
    let match = MatchKindleBooks(
      editions: FakeEditionReader(), digests: CachedFileDigester(digester),
      kindleDigests: kindleDigester(digester), asins: FakeASINScheme(),
      history: InMemorySendHistoryStore())

    for _ in 1...2 {
      let listing = try await library.listing(of: tree.volume, progress: { _, _ in })
      let found = await match([pdf], against: listing.books, on: tree.volume)
      #expect(found.byBook[pdf.id]?.reason == .sameContent)
    }
    #expect(digester.requests.count == 2)
  }
}
