import Foundation
import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct KindleListingCacheTests {
  let tree = try! KindleTree()
  let log = FakeActivityLog()

  func library(device: String = "TEST-UUID") -> USBKindleLibrary {
    USBKindleLibrary(
      cacheDirectory: tree.cache, deviceKey: { _ in device }, freeSpace: { _ in nil }, log: log)
  }

  @Test func aSecondListingReadsOnlyChangedFiles() async throws {
    for name in ["a.txt", "b.txt", "c.txt"] { try tree.write(name, "x") }
    _ = try await library().listing(of: tree.volume, progress: { _, _ in })
    try tree.write("d.txt", "new")
    _ = try await library().listing(of: tree.volume, progress: { _, _ in })
    #expect(
      log.summary.last?.hasPrefix(
        "info USB Read Kindle (device TEST-UUID): 4 books, 1 read and 3 from the cache") == true)
  }

  @Test func aChangedFileIsReadAgain() async throws {
    try tree.write("a.txt", "x")
    _ = try await library().listing(of: tree.volume, progress: { _, _ in })
    try FileManager.default.moveItem(
      at: tree.documents.appending(path: "a.txt"), to: tree.documents.appending(path: "b.txt"))
    #expect(
      try await library().listing(of: tree.volume, progress: { _, _ in }).books.map(\.title)
        == ["b"])
  }

  @Test func aRewrittenFileIsReadAgain() async throws {
    try tree.write("a.txt", "x")
    _ = try await library().listing(of: tree.volume, progress: { _, _ in })
    try tree.write("a.txt", "longer")
    _ = try await library().listing(of: tree.volume, progress: { _, _ in })
    #expect(log.summary.last?.contains("1 read and 0 from the cache") == true)
  }

  @Test func eachKindleHasItsOwnCache() async throws {
    try tree.write("a.txt", "x")
    _ = try await library(device: "ONE").listing(of: tree.volume, progress: { _, _ in })
    _ = try await library(device: "TWO").listing(of: tree.volume, progress: { _, _ in })
    #expect(log.summary.last?.contains("1 read and 0 from the cache") == true)
  }

  @Test func aCachedBookKeepsWhatItsHeadersSaid() async throws {
    let name = "Moby-Dick - Herman Melville.azw3"
    try tree.write(name, MOBIBuilder.book(exth: [(503, "Moby-Dick"), (113, "SN5T2DYX77")]))
    let first = try await library().listing(of: tree.volume, progress: { _, _ in }).books
    let second = try await library().listing(of: tree.volume, progress: { _, _ in }).books
    #expect(second == first)
    #expect(second.first?.asin == "SN5T2DYX77")
  }

  @Test func aCachedBooksSourceIsDetectedAgain() async throws {
    try tree.write(
      "Abreu/Panza de burro - Andrea Abreu.azw3", MOBIBuilder.book(exth: [(503, "Panza de burro")]))
    #expect(
      try await library().listing(of: tree.volume, progress: { _, _ in }).books.first?.source
        == .byHand)
    try tree.writeRoot("metadata.calibre", "[]")
    #expect(
      try await library().listing(of: tree.volume, progress: { _, _ in }).books.first?.source
        == .calibre)
  }

  @Test func anInterruptedListingKeepsTheLastCache() async throws {
    for name in ["a.txt", "b.txt"] { try tree.write(name, "x") }
    _ = try await library().listing(of: tree.volume, progress: { _, _ in })
    let saved = try Data(contentsOf: tree.cacheFile("TEST-UUID"))
    let documents = tree.documents
    _ = try? await library().listing(of: tree.volume) { done, _ in
      if done == 1 { try? FileManager.default.removeItem(at: documents) }
    }
    #expect(try Data(contentsOf: tree.cacheFile("TEST-UUID")) == saved)
  }

  @Test func theCacheHoldsExactlyTheLatestListing() async throws {
    for name in ["a.txt", "b.txt"] { try tree.write(name, "x") }
    _ = try await library().listing(of: tree.volume, progress: { _, _ in })
    try FileManager.default.removeItem(at: tree.documents.appending(path: "b.txt"))
    _ = try await library().listing(of: tree.volume, progress: { _, _ in })
    let cache = KindleListingCache(directory: tree.cache)
    #expect(cache.load(device: "TEST-UUID").keys.sorted() == ["a.txt"])
  }

  @Test func anUnreadableCacheIsIgnored() async throws {
    try tree.write("a.txt", "x")
    try FileManager.default.createDirectory(
      at: tree.cache.appending(path: "kindles"), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: tree.cacheFile("TEST-UUID"))
    #expect(
      try await library().listing(of: tree.volume, progress: { _, _ in }).books.count == 1)
  }

  @Test func aCacheOfAnotherVersionIsIgnored() throws {
    try FileManager.default.createDirectory(
      at: tree.cache.appending(path: "kindles"), withIntermediateDirectories: true)
    try Data(#"{"version": 2, "books": []}"#.utf8).write(to: tree.cacheFile("TEST-UUID"))
    let book = KindleBook.fixture(path: "a.txt")
    let cache = KindleListingCache(directory: tree.cache)
    #expect(cache.load(device: "TEST-UUID").isEmpty)
    cache.save([book], device: "TEST-UUID")
    #expect(cache.load(device: "TEST-UUID") == ["a.txt": book])
  }

  @Test func aDeviceNameCannotEscapeTheCacheFolder() {
    let cache = KindleListingCache(directory: tree.cache)
    cache.save([.fixture(path: "a.txt")], device: "../x:y")
    #expect(cache.load(device: "../x:y").count == 1)
    #expect(
      FileManager.default.fileExists(
        atPath: tree.cache.appending(path: "kindles").appending(path: ".._x_y.json").path))
  }

  @Test func theDeviceIsItsVolumeUUIDOrItsName() {
    #expect(USBKindleLibrary.deviceKey(uuid: "1234-ABCD", name: "Kindle") == "1234-ABCD")
    #expect(USBKindleLibrary.deviceKey(uuid: nil, name: "Kindle") == "Kindle")
  }
}
