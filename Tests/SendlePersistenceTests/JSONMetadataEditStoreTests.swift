import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SendleDomain
import SendlePersistence
import SendleTestSupport
import Testing
import UniformTypeIdentifiers

@Suite(.timeLimit(.minutes(1)))
struct JSONMetadataEditStoreTests {
  let directory: URL
  let id = BookID(rawValue: "ABC123")
  let changedAt = Date(timeIntervalSince1970: 1_800_000_000)

  init() throws {
    directory = try makeTemporaryDirectory()
  }

  private var file: URL { directory.appending(path: "edits.json") }

  private func coverFiles(of store: JSONMetadataEditStore) -> [String] {
    let names = try? FileManager.default.contentsOfDirectory(
      atPath: store.coverFolder.path(percentEncoded: false))
    return (names ?? []).sorted()
  }

  @Test func startsEmptyAndRoundTripsBooksAndWriters() async throws {
    #expect(await JSONMetadataEditStore(directory: directory).edits() == .none)
    let writer = try #require(WriterKey(author: "Eva García Sáenz"))
    let saved = MetadataEdits(
      books: [id: BookEdit(title: "Patria", year: "2016", changedAt: changedAt)],
      writers: [
        writer: WriterEdit(sortName: "García Sáenz, Eva", sortNameChangedAt: changedAt),
        try #require(WriterKey(author: "Fernando Aramburu")): WriterEdit(nameChangedAt: changedAt),
      ])

    try await JSONMetadataEditStore(directory: directory).update(book: id, cover: .keep) {
      $0 = saved
    }

    #expect(await JSONMetadataEditStore(directory: directory).edits() == saved)
  }

  @Test func writesAVersionedFile() async throws {
    try await JSONMetadataEditStore(directory: directory).update(book: id, cover: .keep) {
      $0.books[id] = BookEdit(title: "Patria")
    }

    let data = try Data(contentsOf: file)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["version"] as? Int == 1)
    #expect((json["books"] as? [String: Any])?["ABC123"] != nil)
    #expect(json["writers"] as? [String: Any] != nil)
  }

  @Test func readsAFileFromANewerVersionButNeverRewritesIt() async throws {
    let newer = #"{"books":{"ABC123":{"title":"Patria"}},"version":2,"writers":{}}"#
    try Data(newer.utf8).write(to: file)
    let store = JSONMetadataEditStore(directory: directory)
    try FileManager.default.createDirectory(
      at: store.coverFolder, withIntermediateDirectories: true)
    try Data("newer".utf8).write(to: store.coverFolder.appending(path: "ABC123.webp"))

    #expect(await store.edits().books[id] == BookEdit(title: "Patria"))
    let refused = MetadataEditError.storage(
      .writeFailed("edits.json is from a newer version of Sendle"))
    await #expect(throws: refused) {
      try await store.update(book: id, cover: .replace(try png(width: 10, height: 10))) {
        $0.books[id]?.year = "2016"
      }
    }

    #expect(try String(contentsOf: file, encoding: .utf8) == newer)
    #expect(coverFiles(of: store) == ["ABC123.webp"])
  }

  @Test func ignoresACoverNameThatIsNotAFileInTheCoverFolder() async throws {
    let outside = directory.appending(path: "keep.txt")
    try Data("keep".utf8).write(to: outside)
    let names = ["../keep.txt", "sub/cover.jpg", "/keep.txt", "..", ".", ""]
    var books: [String: [String: String]] = ["ok": ["cover": "ok-0123456789ab.jpg"]]
    for (index, name) in names.enumerated() {
      books["bad\(index)"] = ["title": "Patria", "cover": name]
    }
    let json = ["version": 1, "books": books, "writers": [String: String]()] as [String: Any]
    try JSONSerialization.data(withJSONObject: json).write(to: file)
    let store = JSONMetadataEditStore(directory: directory)

    let edits = await store.edits()
    #expect(edits.books[BookID(rawValue: "ok")]?.cover == "ok-0123456789ab.jpg")
    for index in names.indices {
      #expect(edits.books[BookID(rawValue: "bad\(index)")] == BookEdit(title: "Patria"))
    }

    let traversing = #"{"books":{"ABC123":{"cover":"../keep.txt"}},"version":1,"writers":{}}"#
    try Data(traversing.utf8).write(to: file)
    try FileManager.default.createDirectory(
      at: store.coverFolder, withIntermediateDirectories: true)
    try await store.update(book: id, cover: .keep) { $0.books = [:] }

    #expect(FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)))
  }

  @Test func appliesTheChangeAndKeepsTheCoverWhenAskedTo() async throws {
    let store = JSONMetadataEditStore(directory: directory)
    try await store.update(book: id, cover: .replace(try png(width: 100, height: 150))) {
      $0.books[id] = BookEdit(title: "Patria")
    }
    let cover = try #require(await store.edits().books[id]?.cover)

    try await store.update(book: id, cover: .keep) { $0.books[id]?.year = "2016" }

    let edit = try #require(await store.edits().books[id])
    #expect(edit.cover == cover)
    #expect(edit.title == "Patria")
    #expect(edit.year == "2016")
    #expect(coverFiles(of: store) == [cover])
  }

  @Test func quarantinesAnUnreadableFile() async throws {
    try Data("{ not json".utf8).write(to: file)

    #expect(await JSONMetadataEditStore(directory: directory).edits() == .none)

    let names = try FileManager.default.contentsOfDirectory(
      atPath: directory.path(percentEncoded: false))
    let moved = try #require(names.first { $0.wholeMatch(of: /edits\.corrupt-\d+\.json/) != nil })
    #expect(
      try String(contentsOf: directory.appending(path: moved), encoding: .utf8) == "{ not json")
    #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
  }

  @Test func aCorruptEditStoreStillLoadsTheLibrary() async throws {
    try Data("{ not json".utf8).write(to: file)
    let book = Book.fixture(id: "A1", title: "Patria")
    let load = LoadLibrary(
      library: FakeBooksLibrary(.success([book])), inspector: StubProtectionInspector(),
      edits: JSONMetadataEditStore(directory: directory))

    let books = try await load()

    #expect(books.map(\.title) == ["Patria"])
    #expect(books.first?.edits.isEdited == false)
  }

  @Test func replacesACoverWithAScaledJPEGNamedByItsContents() async throws {
    let store = JSONMetadataEditStore(directory: directory)

    try await store.update(book: id, cover: .replace(try png(width: 3000, height: 4500))) { _ in }

    let name = try #require(await store.edits().books[id]?.cover)
    #expect(name.wholeMatch(of: /ABC123-[0-9a-f]{12}\.jpg/) != nil)
    let stored = try Data(contentsOf: store.coverFolder.appending(path: name))
    #expect(name == "ABC123-\(digest(of: stored)).jpg")
    #expect(stored.starts(with: [0xFF, 0xD8, 0xFF]))
    let size = try #require(pixelSize(of: stored))
    #expect(size.height == 2560)
    #expect(size.width == 1707)
    #expect(coverFiles(of: store) == [name])
  }

  @Test func keepsASmallImageAtItsOwnSize() async throws {
    let store = JSONMetadataEditStore(directory: directory)

    try await store.update(book: id, cover: .replace(try png(width: 200, height: 300))) { _ in }

    let name = try #require(await store.edits().books[id]?.cover)
    let size = pixelSize(of: try Data(contentsOf: store.coverFolder.appending(path: name)))
    #expect(size?.width == 200)
    #expect(size?.height == 300)
  }

  @Test func flattensTransparencyOntoWhite() async throws {
    let store = JSONMetadataEditStore(directory: directory)
    let clear = try png(width: 40, height: 40, red: 0, alpha: 0)

    try await store.update(book: id, cover: .replace(clear)) { _ in }

    let name = try #require(await store.edits().books[id]?.cover)
    let stored = try Data(contentsOf: store.coverFolder.appending(path: name))
    let pixel = try #require(centrePixel(of: stored))
    #expect(pixel.allSatisfy { $0 > 240 })
  }

  @Test func namesTheFileWithAPathSafeID() async throws {
    let store = JSONMetadataEditStore(directory: directory)
    let awkward = BookID(rawValue: "a/b c")

    try await store.update(book: awkward, cover: .replace(try png(width: 10, height: 10))) { _ in }

    let name = try #require(await store.edits().books[awkward]?.cover)
    #expect(name.wholeMatch(of: /a%2Fb%20c-[0-9a-f]{12}\.jpg/) != nil)
    #expect(coverFiles(of: store) == [name])

    try await store.update(book: awkward, cover: .replace(try png(width: 10, height: 10, red: 0))) {
      _ in
    }

    let replaced = try #require(await store.edits().books[awkward]?.cover)
    #expect(replaced != name)
    #expect(coverFiles(of: store) == [replaced])
  }

  @Test func replacingAgainDeletesTheOldFileOnlyAfterSaving() async throws {
    let store = JSONMetadataEditStore(directory: directory)
    try await store.update(book: id, cover: .replace(try png(width: 100, height: 150))) { _ in }
    let old = try #require(await store.edits().books[id]?.cover)

    try await store.update(book: id, cover: .replace(try png(width: 100, height: 150, red: 0))) {
      _ in
    }

    let new = try #require(await store.edits().books[id]?.cover)
    #expect(new != old)
    #expect(coverFiles(of: store) == [new])
  }

  @Test func keepsTheOldCoverAndLeavesNothingBehindWhenTheSaveFails() async throws {
    let store = JSONMetadataEditStore(directory: directory)
    try await store.update(book: id, cover: .replace(try png(width: 100, height: 150))) {
      $0.books[id] = BookEdit(title: "Patria")
    }
    let before = await store.edits()
    let old = try #require(before.books[id]?.cover)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: directory.path(percentEncoded: false))
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: directory.path(percentEncoded: false))
    }

    await #expect(throws: MetadataEditError.self) {
      try await store.update(book: id, cover: .replace(try png(width: 100, height: 150, red: 0))) {
        $0.books[id]?.title = "Changed"
      }
    }

    #expect(await store.edits() == before)
    #expect(coverFiles(of: store) == [old])
  }

  @Test func replacingACoverWithTheSameImageKeepsItsFile() async throws {
    let store = JSONMetadataEditStore(directory: directory)
    let image = try png(width: 100, height: 150)
    try await store.update(book: id, cover: .replace(image)) { _ in }
    let name = try #require(await store.edits().books[id]?.cover)

    try await store.update(book: id, cover: .replace(image)) { _ in }

    #expect(await store.edits().books[id]?.cover == name)
    #expect(coverFiles(of: store) == [name])
  }

  @Test func revertingACoverDeletesItsFile() async throws {
    let store = JSONMetadataEditStore(directory: directory)
    try await store.update(book: id, cover: .replace(try png(width: 100, height: 150))) {
      $0.books[id] = BookEdit(title: "Patria")
    }

    try await store.update(book: id, cover: .revert) { _ in }

    let edit = try #require(await store.edits().books[id])
    #expect(edit.cover == nil)
    #expect(edit.title == "Patria")
    #expect(coverFiles(of: store) == [])
  }

  @Test func deletesTheCoverFileOfAnEditTheChangeRemoves() async throws {
    let store = JSONMetadataEditStore(directory: directory)
    try await store.update(book: id, cover: .replace(try png(width: 100, height: 150))) { _ in }

    try await store.update(book: id, cover: .keep) { $0.books[id] = nil }

    #expect(await store.edits() == .none)
    #expect(coverFiles(of: store) == [])
  }

  @Test func refusesDataThatIsNotAnImage() async throws {
    let store = JSONMetadataEditStore(directory: directory)

    await #expect(throws: MetadataEditError.unreadableImage) {
      try await store.update(book: id, cover: .replace(Data("not an image".utf8))) {
        $0.books[id] = BookEdit(title: "Patria")
      }
    }

    #expect(await store.edits() == .none)
    #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    #expect(!FileManager.default.fileExists(atPath: store.coverFolder.path(percentEncoded: false)))
  }

  @Test func refusesImagesOver20MB() async throws {
    let store = JSONMetadataEditStore(directory: directory)
    let header: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    let tooLarge = Data(header + [UInt8](repeating: 0, count: 20_000_001 - header.count))

    await #expect(throws: MetadataEditError.imageTooLarge) {
      try await store.update(book: id, cover: .replace(tooLarge)) { _ in }
    }

    #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    #expect(!FileManager.default.fileExists(atPath: store.coverFolder.path(percentEncoded: false)))
  }

  @Test func deletesCoverFilesNoEditUses() async throws {
    let store = JSONMetadataEditStore(directory: directory)
    try await store.update(book: id, cover: .replace(try png(width: 100, height: 150))) { _ in }
    let used = try #require(await store.edits().books[id]?.cover)
    let stray = store.coverFolder.appending(path: "GONE-0123456789ab.jpg")
    try Data("old".utf8).write(to: stray)

    let afterLaunch = JSONMetadataEditStore(directory: directory)
    _ = await afterLaunch.edits()

    #expect(coverFiles(of: afterLaunch) == [used])
  }

  @Test func sweepsUnusedCoversInAFolderWhoseNameHasASpace() async throws {
    let spaced = directory.appending(path: "Application Support", directoryHint: .isDirectory)
    let store = JSONMetadataEditStore(directory: spaced)
    try await store.update(book: id, cover: .replace(try png(width: 100, height: 150))) { _ in }
    let used = try #require(await store.edits().books[id]?.cover)
    try Data("old".utf8).write(to: store.coverFolder.appending(path: "GONE-0123456789ab.jpg"))

    let afterLaunch = JSONMetadataEditStore(directory: spaced)
    _ = await afterLaunch.edits()

    #expect(coverFiles(of: afterLaunch) == [used])
  }

  @Test func keepsCoverFilesWhileTheEditsFileCouldNotBeRead() async throws {
    let store = JSONMetadataEditStore(directory: directory)
    try await store.update(book: id, cover: .replace(try png(width: 100, height: 150))) { _ in }
    let used = try #require(await store.edits().books[id]?.cover)
    try Data("{ not json".utf8).write(to: file)

    let afterLaunch = JSONMetadataEditStore(directory: directory)
    #expect(await afterLaunch.edits() == .none)
    #expect(await afterLaunch.edits() == .none)

    #expect(coverFiles(of: afterLaunch) == [used])
  }

  @Test func logsASaveThatFailed() async throws {
    let blocked = directory.appending(path: "file-not-folder")
    try Data().write(to: blocked)
    let log = FakeActivityLog()
    let store = JSONMetadataEditStore(directory: blocked, log: log)

    do {
      try await store.update(book: id, cover: .keep) { $0.books[id] = BookEdit(title: "Patria") }
      Issue.record("The save should have failed")
    } catch {
      guard case .storage(.writeFailed) = error else {
        Issue.record("Unexpected error \(error)")
        return
      }
    }

    #expect(log.summary.contains { $0.hasPrefix("error APP Couldn't save edits.json: ") })
  }
}

private func png(
  width: Int, height: Int, red: CGFloat = 1, alpha: CGFloat = 1
) throws -> Data {
  struct Failure: Error {}
  guard let space = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { throw Failure() }
  context.setFillColor(CGColor(red: red, green: 0, blue: 1 - red, alpha: alpha))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  let data = NSMutableData()
  guard let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithData(
      data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
  else { throw Failure() }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { throw Failure() }
  return data as Data
}

private func pixelSize(of data: Data) -> (width: Int, height: Int)? {
  guard let source = CGImageSourceCreateWithData(data as CFData, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { return nil }
  return (image.width, image.height)
}

/// The 0–255 RGB colour of the image's centre pixel.
private func centrePixel(of data: Data) -> [UInt8]? {
  guard let source = CGImageSourceCreateWithData(data as CFData, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
    let space = CGColorSpace(name: CGColorSpace.sRGB)
  else { return nil }
  var pixel = [UInt8](repeating: 0, count: 4)
  let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
    guard
      let context = CGContext(
        data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    context.draw(
      image,
      in: CGRect(
        x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
        width: CGFloat(image.width), height: CGFloat(image.height)))
    return true
  }
  return drawn ? Array(pixel.prefix(3)) : nil
}

private func digest(of data: Data) -> String {
  SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
}
