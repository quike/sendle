import CryptoKit
import Foundation
import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing

struct KindleCoversTests {
  let tree: KindleTree

  init() throws {
    tree = try KindleTree()
  }

  @Test func prefersTheKindlesOwnThumbnail() throws {
    try tree.write(
      "a.azw3",
      MOBIBuilder.book(
        exth: [(113, "SN5T2DYX77"), (501, "EBOK")], cover: makeJPEG(width: 80, height: 110)))
    try tree.writeRoot(
      "system/thumbnails/thumbnail_SN5T2DYX77_EBOK_portrait.jpg",
      makeJPEG(width: 300, height: 450))
    let png = try #require(
      KindleCovers.cover(
        of: .fixture(path: "a.azw3", asin: "SN5T2DYX77", documentType: "EBOK"),
        onKindleAt: tree.root, maxPixel: 120
      ).png)
    #expect(pixelSize(of: png) == CGSize(width: 80, height: 120))
  }

  @Test func fallsBackToTheEmbeddedCover() throws {
    try tree.write(
      "a.azw3",
      MOBIBuilder.book(
        exth: [(113, "SN5T2DYX77"), (501, "EBOK")], cover: makeJPEG(width: 80, height: 110)))
    let png = KindleCovers.cover(
      of: .fixture(path: "a.azw3", asin: "SN5T2DYX77", documentType: "EBOK"),
      onKindleAt: tree.root, maxPixel: 360
    ).png
    #expect(png.flatMap(pixelSize) == CGSize(width: 80, height: 110))
  }

  @Test func readsTheEmbeddedCoverOfABookWithoutAnASIN() throws {
    try tree.write(
      "Moby-Dick - Herman Melville.azw3",
      MOBIBuilder.book(exth: [(503, "Moby-Dick")], cover: makeJPEG(width: 80, height: 110)))
    #expect(
      KindleCovers.cover(
        of: .fixture(path: "Moby-Dick - Herman Melville.azw3"), onKindleAt: tree.root,
        maxPixel: 120
      ).png != nil)
  }

  @Test func drawsAPDFsFirstPage() throws {
    try tree.write("1984.pdf", makePDF(title: nil, author: nil))
    let png = KindleCovers.cover(
      of: .fixture(path: "1984.pdf"), onKindleAt: tree.root, maxPixel: 120
    ).png
    let size = try #require(png.flatMap(pixelSize))
    #expect(max(size.width, size.height) <= 120)
    #expect(size.height > size.width)
  }

  @Test func aTextFileHasNoCoverAndAMissingFileIsUnreadable() throws {
    try tree.write("notes.txt", "x")
    #expect(
      KindleCovers.cover(of: .fixture(path: "notes.txt"), onKindleAt: tree.root, maxPixel: 120)
        == .none)
    #expect(
      KindleCovers.cover(of: .fixture(path: "gone.azw3"), onKindleAt: tree.root, maxPixel: 120)
        == .unreadable)
  }

  @Test func aBookWithoutACoverOrWithDamagedHeadersHasNone() throws {
    try tree.write("plain.azw3", MOBIBuilder.book(exth: [(503, "Plain")]))
    try tree.write("damaged.azw3", MOBIBuilder.book(exth: [(503, "X")]).prefix(120))
    for path in ["plain.azw3", "damaged.azw3"] {
      #expect(
        KindleCovers.cover(of: .fixture(path: path), onKindleAt: tree.root, maxPixel: 120)
          == .none)
    }
  }

  @Test func aBookItCannotOpenIsUnreadableNotCoverless() throws {
    for name in ["a.azw3", "b.pdf"] { try tree.write(name, "x") }
    let files = ["a.azw3", "b.pdf"].map { tree.documents.appending(path: $0).path }
    for file in files {
      try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file)
    }
    defer {
      for file in files {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file)
      }
    }
    for path in ["a.azw3", "b.pdf"] {
      #expect(
        KindleCovers.cover(of: .fixture(path: path), onKindleAt: tree.root, maxPixel: 120)
          == .unreadable)
    }
  }

  @Test func anOversizedEmbeddedCoverIsLeftAlone() throws {
    let cover = makeJPEG(width: 80, height: 110) + Data(count: 9 << 20)
    try tree.write("big.azw3", MOBIBuilder.book(exth: [(503, "Big")], cover: cover))
    #expect(
      KindleCovers.cover(of: .fixture(path: "big.azw3"), onKindleAt: tree.root, maxPixel: 120)
        == .none)
  }

  @Test func aCancelledCoverReadsNothing() async throws {
    try tree.write(
      "a.azw3", MOBIBuilder.book(exth: [(503, "A")], cover: makeJPEG(width: 80, height: 110)))
    let library = USBKindleLibrary(
      cacheDirectory: tree.cache, deviceKey: { _ in "K" }, freeSpace: { _ in nil },
      log: FakeActivityLog())
    let volume = tree.volume
    let started = Signal()
    let task = Task {
      await started.wait()
      return await library.cover(of: .fixture(path: "a.azw3"), on: volume, maxPixel: 120)
    }
    task.cancel()
    await started.fire()
    #expect(await task.value == .unreadable)
  }

  @Test func neverWritesToTheKindle() throws {
    try tree.write(
      "a.azw3",
      MOBIBuilder.book(
        exth: [(113, "SN5T2DYX77"), (501, "EBOK")], cover: makeJPEG(width: 80, height: 110)))
    let before = try FileManager.default.subpathsOfDirectory(atPath: tree.root.path).sorted()
    _ = KindleCovers.cover(
      of: .fixture(path: "a.azw3", asin: "SN5T2DYX77", documentType: "EBOK"),
      onKindleAt: tree.root, maxPixel: 120)
    #expect(try FileManager.default.subpathsOfDirectory(atPath: tree.root.path).sorted() == before)
  }

  @Test func theLibraryDrawsACoverOnItsVolume() async throws {
    try tree.write("1984.pdf", makePDF(title: nil, author: nil))
    let library = USBKindleLibrary(
      cacheDirectory: tree.cache, deviceKey: { _ in "K" }, freeSpace: { _ in nil },
      log: FakeActivityLog())
    #expect(
      await library.cover(of: .fixture(path: "1984.pdf"), on: tree.volume, maxPixel: 120).png
        != nil)
  }

  @Test func hashesAFile() async throws {
    let url = try makeTemporaryDirectory().appending(path: "abc")
    try Data("abc".utf8).write(to: url)
    #expect(
      await SHA256FileDigester().sha256(of: url)
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(await SHA256FileDigester().sha256(of: url.appending(path: "missing")) == nil)
  }

  @Test func hashesAFileLargerThanOneChunk() async throws {
    let url = try makeTemporaryDirectory().appending(path: "big")
    let data = Data((0..<(2_621_440 + 7)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    try data.write(to: url)
    let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    #expect(await SHA256FileDigester().sha256(of: url) == expected)
  }

  @Test func hashesAnEmptyFile() async throws {
    let url = try makeTemporaryDirectory().appending(path: "empty")
    try Data().write(to: url)
    #expect(
      await SHA256FileDigester().sha256(of: url)
        == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  }
}
