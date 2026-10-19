import Darwin
import Foundation
import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct USBDeliveryChannelTests {
  let root: URL
  let documents: URL
  let book: URL
  let contents: Data

  init() throws {
    root = try makeVolumeRoot()
    documents = root.appending(path: "documents", directoryHint: .isDirectory)
    let folder = try makeTemporaryDirectory()
    book = folder.appending(path: "book.pdf")
    contents = Data((0..<3_584).map { UInt8($0 % 251) })
    try contents.write(to: book)
  }

  var kindle: KindleVolume { KindleVolume(id: root.path, name: "Kindle", mountURL: root) }

  let log = FakeActivityLog()

  func channel(freeSpace: Int64? = nil) -> USBDeliveryChannel {
    USBDeliveryChannel(volume: kindle, chunkSize: 1_024, freeSpace: { _ in freeSpace }, log: log)
  }

  func send(
    _ channel: USBDeliveryChannel,
    progress: @escaping @Sendable (Double) async -> Void = { _ in }
  ) async -> SendFailure? {
    do throws(SendFailure) {
      try await channel.deliver(
        PreparedFile(url: book, format: .pdf), named: "Moby-Dick - Herman Melville",
        progress: progress)
      return nil
    } catch {
      return error
    }
  }

  func documentNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: documents.path).sorted()
  }

  @Test func copiesTheBookIntoDocumentsUnderItsName() async throws {
    #expect(await send(channel()) == nil)

    #expect(try documentNames() == ["Moby-Dick - Herman Melville.pdf"])
    #expect(
      try Data(contentsOf: documents.appending(path: "Moby-Dick - Herman Melville.pdf")) == contents
    )
  }

  @Test func reportsProgressAsItCopies() async {
    let fractions = Recorder<Double>()

    _ = await send(channel()) { await fractions.record($0) }

    let values = await fractions.values
    #expect(values == values.sorted())
    #expect(values.count == 4)
    #expect(values.last == 1)
  }

  @Test func replacesAnEarlierCopyOfTheSameBook() async throws {
    let earlier = documents.appending(path: "Moby-Dick - Herman Melville.pdf")
    try Data("old".utf8).write(to: earlier)

    #expect(await send(channel()) == nil)

    #expect(try Data(contentsOf: earlier) == contents)
  }

  @Test func refusesABookLargerThanTheFreeSpace() async throws {
    #expect(await send(channel(freeSpace: 3_000)) == .diskFull)

    #expect(try documentNames().isEmpty)
    #expect(log.summary.last == "error USB Kindle has 3 KB free; the book needs 4 KB")
  }

  @Test func logsTheCopy() async {
    _ = await send(channel(freeSpace: 3_100_000_000))

    #expect(
      log.summary == [
        "info USB Copying 4 KB to Kindle (3.1 GB free)",
        "info USB Saved documents/Moby-Dick - Herman Melville.pdf and flushed it to the Kindle",
      ])
  }

  @Test func removesTheAttributesFileMacOSWritesBesideTheBook() async throws {
    try Data("attributes".utf8).write(
      to: documents.appending(path: "._Moby-Dick - Herman Melville.pdf"))

    #expect(await send(channel()) == nil)

    #expect(try documentNames() == ["Moby-Dick - Herman Melville.pdf"])
    #expect(
      log.summary.suffix(2) == [
        "debug USB Removed ._Moby-Dick - Herman Melville.pdf, macOS's attributes file",
        "info USB Saved documents/Moby-Dick - Herman Melville.pdf and flushed it to the Kindle",
      ])
  }

  @Test func aKindleWithoutItsDocumentsFolderIsGone() async throws {
    try FileManager.default.removeItem(at: documents)

    #expect(await send(channel()) == .deviceDisconnected)
  }

  @Test func aKindleThatDisappearsMidCopyWasUnplugged() async {
    let root = root

    let failure = await send(channel()) { _ in try? FileManager.default.removeItem(at: root) }

    #expect(failure == .deviceDisconnected)
    #expect(log.summary.last == "error USB Stopped copying: the Kindle was unplugged")
  }

  @Test func cancellingStopsTheCopyAndLeavesNothingBehind() async throws {
    let failure = await send(channel()) { _ in withUnsafeCurrentTask { $0?.cancel() } }

    #expect(failure == .cancelled)
    #expect(try documentNames().isEmpty)
    #expect(log.summary.last == "info USB Copy cancelled")
  }

  @Test func clearsWhatAnInterruptedCopyLeftBehind() async throws {
    try Data("half".utf8).write(to: documents.appending(path: ".sendle-OLD.partial"))
    try Data("keep".utf8).write(to: documents.appending(path: "Dracula.azw3"))

    #expect(await send(channel()) == nil)

    #expect(try documentNames() == ["Dracula.azw3", "Moby-Dick - Herman Melville.pdf"])
    #expect(log.summary.first == "debug USB Removed 1 unfinished copy from an earlier send")
  }

  @Test func aBookThatIsGoneIsMissing() async throws {
    try FileManager.default.removeItem(at: book)

    #expect(await send(channel()) == .missing)
  }

  @Test func explainsAKindleItCannotWriteTo() async throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: documents.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: documents.path)
    }

    #expect(await send(channel()) == .copyFailed("Permission denied"))
  }

  // MARK: Covers

  var thumbnails: URL { root.appending(path: "system/thumbnails", directoryHint: .isDirectory) }

  /// The ASIN a book delivered as "Moby-Dick - Herman Melville" gets without a seed.
  var namedASIN: String { AZW3Metadata.asin(for: "Moby-Dick - Herman Melville") }

  var thumbnail: URL { thumbnails.appending(path: "thumbnail_\(namedASIN)_EBOK_portrait.jpg") }

  func send(azw3: Data) async throws -> SendFailure? {
    let url = try makeTemporaryDirectory().appending(path: "book.azw3")
    try azw3.write(to: url)
    do throws(SendFailure) {
      try await channel().deliver(
        PreparedFile(url: url, format: .azw3), named: "Moby-Dick - Herman Melville",
        progress: { _ in })
      return nil
    } catch {
      return error
    }
  }

  @Test func writesTheCoverWhereTheKindlesLibraryLooksForIt() async throws {
    let cover = makeJPEG(width: 800, height: 1_104)

    #expect(try await send(azw3: makeAZW3(asin: "SN2Q7KXA4B", cover: cover)) == nil)

    let size = try #require(pixelSize(of: Data(contentsOf: thumbnail)))
    #expect(size.height == 500)
    #expect(abs(size.width - 362) <= 1)
    #expect(
      log.summary.last
        == "info USB Wrote the cover to system/thumbnails/thumbnail_\(namedASIN)_EBOK_portrait.jpg")
  }

  @Test func replacesTheCoverTheKindleFoundForItself() async throws {
    try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
    try Data("No image available".utf8).write(to: thumbnail)

    _ = try await send(azw3: makeAZW3(asin: "SN2Q7KXA4B", cover: makeJPEG(width: 80, height: 110)))

    #expect(pixelSize(of: try Data(contentsOf: thumbnail)) == CGSize(width: 80, height: 110))
  }

  func deliverAZW3(_ data: Data, seed: String?, named name: String) async throws -> Data {
    let url = try makeTemporaryDirectory().appending(path: "book.azw3")
    try data.write(to: url)
    try await channel().deliver(
      PreparedFile(url: url, format: .azw3, asinSeed: seed), named: name, progress: { _ in })
    return try Data(contentsOf: documents.appending(path: "\(name).azw3"))
  }

  @Test func stampsTheASINOfTheEditionKey() async throws {
    let copy = try await deliverAZW3(
      makeAZW3(asin: "EBOK000000", cover: makeJPEG(width: 80, height: 110)),
      seed: "edition:urn:uuid:moby-dick#2", named: "Moby-Dick - Herman Melville (2)")

    let asin = AZW3Metadata.asin(for: "edition:urn:uuid:moby-dick#2")
    #expect(AZW3Metadata(copy)?.asin == asin)
    #expect(
      FileManager.default.fileExists(
        atPath: thumbnails.appending(path: "thumbnail_\(asin)_EBOK_portrait.jpg").path))
    #expect(log.summary.contains("info USB Set the book's ASIN to \(asin)"))
  }

  @Test func withoutASeedTheASINFollowsTheDeliveredName() async throws {
    let copy = try await deliverAZW3(
      makeAZW3(asin: "EBOK000000"), seed: nil, named: "Moby-Dick - Herman Melville")

    #expect(AZW3Metadata(copy)?.asin == namedASIN)
  }

  @Test func changesOnlyTheTenASINBytes() async throws {
    let original = MOBIBuilder.book(
      fullName: "MOBYDICK",
      exth: [
        (503, "Moby-Dick"), (100, "Herman Melville"), (113, "EBOK000000"), (501, "EBOK"),
        (104, "9780306406157"),
      ], cover: makeJPEG(width: 80, height: 110))

    let copy = try await deliverAZW3(
      original, seed: "edition:urn:uuid:moby-dick", named: "Moby-Dick - Herman Melville")

    #expect(copy.count == original.count)
    #expect(zip(original, copy).filter { $0.0 != $0.1 }.count <= 10)
    #expect(MobiMetadata(DataBytes(copy))?.title == "Moby-Dick")
    #expect(MobiMetadata(DataBytes(copy))?.isbn == "9780306406157")
  }

  @Test func aBookWithoutATenCharacterASINIsCopiedUnchanged() async throws {
    let original = MOBIBuilder.book(exth: [(113, "SHORT"), (501, "EBOK")])

    let copy = try await deliverAZW3(
      original, seed: "edition:k", named: "Moby-Dick - Herman Melville")

    #expect(copy == original)
    #expect(
      log.summary.contains(
        "warning USB Couldn't set the book's ASIN; the Kindle may mix up its cover"))
  }

  @Test func aBookWithoutACoverGetsNoThumbnail() async throws {
    #expect(try await send(azw3: makeAZW3(asin: "SN2Q7KXA4B")) == nil)

    #expect(!FileManager.default.fileExists(atPath: thumbnails.path))
    #expect(log.summary.last == "debug USB The book has no cover, so the Kindle gets no thumbnail")
  }

  @Test func aPDFGetsNoThumbnail() async throws {
    #expect(await send(channel()) == nil)

    #expect(!FileManager.default.fileExists(atPath: thumbnails.path))
  }

  /// On FAT, macOS keeps a new file's extended attributes in a `._` file beside it.
  @Test func removesTheFilesMacOSAddsBesideTheBookAndItsCover() async throws {
    try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
    let besideBook = documents.appending(path: "._Moby-Dick - Herman Melville.azw3")
    let besideCover = thumbnails.appending(path: "._thumbnail_\(namedASIN)_EBOK_portrait.jpg")
    for file in [besideBook, besideCover] { try Data("Mac OS X".utf8).write(to: file) }

    _ = try await send(azw3: makeAZW3(asin: "SN2Q7KXA4B", cover: makeJPEG(width: 80, height: 110)))

    #expect(!FileManager.default.fileExists(atPath: besideBook.path))
    #expect(!FileManager.default.fileExists(atPath: besideCover.path))
    #expect(FileManager.default.fileExists(atPath: thumbnail.path))
  }

  @Test func aKindleWithoutASystemFolderStillGetsTheBook() async throws {
    try FileManager.default.removeItem(at: root.appending(path: "system"))

    #expect(try await send(azw3: makeAZW3(cover: makeJPEG(width: 80, height: 110))) == nil)

    #expect(try documentNames() == ["Moby-Dick - Herman Melville.azw3"])
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "system").path))
    #expect(
      log.summary.last == "debug USB The Kindle has no system folder, so it gets no thumbnail")
  }

  @Test(
    arguments: [
      (ENOSPC, true, SendFailure.diskFull),
      (EDQUOT, true, .diskFull),
      (EIO, true, .deviceDisconnected),
      (ENXIO, true, .deviceDisconnected),
      (EROFS, true, .copyFailed("Read-only file system")),
      (EROFS, false, .deviceDisconnected),
    ] as [(Int32, Bool, SendFailure)])
  func explainsAFailedWrite(code: Int32, isMounted: Bool, failure: SendFailure) {
    #expect(USBDeliveryChannel.failure(errno: code, volumeIsMounted: isMounted) == failure)
  }
}
