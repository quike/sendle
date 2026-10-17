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

  func channel(freeSpace: Int64? = nil) -> USBDeliveryChannel {
    USBDeliveryChannel(volume: kindle, chunkSize: 1_024, freeSpace: { _ in freeSpace })
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
  }

  @Test func aKindleWithoutItsDocumentsFolderIsGone() async throws {
    try FileManager.default.removeItem(at: documents)

    #expect(await send(channel()) == .deviceDisconnected)
  }

  @Test func aKindleThatDisappearsMidCopyWasUnplugged() async {
    let root = root

    let failure = await send(channel()) { _ in try? FileManager.default.removeItem(at: root) }

    #expect(failure == .deviceDisconnected)
  }

  @Test func cancellingStopsTheCopyAndLeavesNothingBehind() async throws {
    let failure = await send(channel()) { _ in withUnsafeCurrentTask { $0?.cancel() } }

    #expect(failure == .cancelled)
    #expect(try documentNames().isEmpty)
  }

  @Test func clearsWhatAnInterruptedCopyLeftBehind() async throws {
    try Data("half".utf8).write(to: documents.appending(path: ".sendle-OLD.partial"))
    try Data("keep".utf8).write(to: documents.appending(path: "Dracula.azw3"))

    #expect(await send(channel()) == nil)

    #expect(try documentNames() == ["Dracula.azw3", "Moby-Dick - Herman Melville.pdf"])
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
