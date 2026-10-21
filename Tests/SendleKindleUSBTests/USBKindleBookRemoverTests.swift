import Foundation
import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing
import os

@Suite(.timeLimit(.minutes(1)))
struct USBKindleBookRemoverTests {
  let tree = try! KindleTree()
  let alice = "Alice's Adventures in Wonderland - Lewis Carroll"
  let moby = "Moby Dick; Or, The Whale - Herman Melville"
  let thumbnail = "system/thumbnails/thumbnail_SNALICE001_EBOK_portrait.jpg"
  let thumbnailTwin = "system/thumbnails/._thumbnail_SNALICE001_EBOK_portrait.jpg"
  let holding = USBKindleBookRemover.holdingFolder

  /// Alice with every part a book can have, and Moby Dick beside her with its own sidecar.
  private func writeAliceAndMoby() throws {
    try tree.write("\(alice).azw3", makeAZW3(asin: "SNALICE001", type: "EBOK"))
    try tree.write("._\(alice).azw3", "attributes")
    try tree.write("\(alice).sdr/\(alice).azw3f", "position")
    try tree.write("\(alice).sdr/\(alice).azw3r", "highlights")
    try tree.writeRoot(thumbnail, makeJPEG(width: 8, height: 12))
    try tree.writeRoot(thumbnailTwin, "attributes")
    try tree.write("\(moby).azw3", makeAZW3(asin: "SNMOBY0001", type: "EBOK"))
    try tree.write("\(moby).sdr/\(moby).azw3f", "position")
  }

  private var alicesFiles: [String] {
    [
      "documents/\(alice).azw3", "documents/._\(alice).azw3",
      "documents/\(alice).sdr/\(alice).azw3f", "documents/\(alice).sdr/\(alice).azw3r",
      thumbnail, thumbnailTwin,
    ]
  }

  private func listing() async throws -> [KindleBook] {
    try await USBKindleLibrary(
      cacheDirectory: tree.cache, deviceKey: { _ in "TEST" }, freeSpace: { _ in nil },
      log: NoActivityLog()
    ).listing(of: tree.volume, progress: { _, _ in }).books
  }

  private func book(_ path: String, in books: [KindleBook]) throws -> KindleBook {
    try #require(books.first { $0.id.relativePath == path })
  }

  private func names(_ path: String) -> [String] {
    let folder = tree.root.appending(path: path).path
    return ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted()
  }

  private func exists(_ path: String) -> Bool {
    var info = stat()
    return lstat(tree.root.appending(path: path).path, &info) == 0
  }

  private func contents(_ paths: [String]) throws -> [Data] {
    try paths.map { try Data(contentsOf: tree.root.appending(path: $0)) }
  }

  @Test func holdMovesOnlyTheBooksOwnFilesAside() async throws {
    try writeAliceAndMoby()
    let books = try await listing()

    let held = try await USBKindleBookRemover().hold(
      book("\(alice).azw3", in: books), listedWith: books, on: tree.volume)

    #expect(names("documents") == ["\(moby).azw3", "\(moby).sdr"])
    #expect(names("system/thumbnails") == [])
    let aside = names("\(holding)/\(held.id.uuidString)")
    #expect(aside.count == 5)
    #expect(aside.allSatisfy { $0.hasSuffix(".held") })
    #expect(held.parts == [.book, .sidecar, .cover])
  }

  @Test func undoPutsBackByteIdenticalFiles() async throws {
    try writeAliceAndMoby()
    let before = try contents(alicesFiles)
    let books = try await listing()
    let remover = USBKindleBookRemover()
    let held = try await remover.hold(
      book("\(alice).azw3", in: books), listedWith: books, on: tree.volume)

    try await remover.restore(held)

    #expect(try contents(alicesFiles) == before)
    #expect(!exists(holding))
  }

  @Test func finalizeRemovesItAndItsEmptyAuthorFolder() async throws {
    try tree.write("Abreu, Andrea/Panza.azw3", makeAZW3())
    let calibre = #"[{"title": "Panza de burro"}]"#
    try tree.writeRoot("metadata.calibre", calibre)
    let books = try await listing()
    let remover = USBKindleBookRemover()
    let held = try await remover.hold(
      book("Abreu, Andrea/Panza.azw3", in: books), listedWith: books, on: tree.volume)

    try await remover.finalize(held)

    #expect(!exists("documents/Abreu, Andrea"))
    #expect(!exists(holding))
    #expect(
      try String(contentsOf: tree.root.appending(path: "metadata.calibre"), encoding: .utf8)
        == calibre)
  }

  @Test func anAuthorFolderWithOtherFilesStays() async throws {
    try tree.write("Abreu, Andrea/Panza.azw3", makeAZW3())
    try tree.write("Abreu, Andrea/cover.jpg", makeJPEG(width: 8, height: 12))
    let books = try await listing()
    let remover = USBKindleBookRemover()
    let held = try await remover.hold(
      book("Abreu, Andrea/Panza.azw3", in: books), listedWith: books, on: tree.volume)

    try await remover.finalize(held)

    #expect(names("documents/Abreu, Andrea") == ["cover.jpg"])
  }

  @Test func missingPartsAreNotErrors() async throws {
    try tree.write("Dracula - Bram Stoker.pdf", makePDF(title: "Dracula", author: "Bram Stoker"))
    let books = try await listing()
    let remover = USBKindleBookRemover()

    let held = try await remover.hold(
      book("Dracula - Bram Stoker.pdf", in: books), listedWith: books, on: tree.volume)
    #expect(held.parts == [.book])
    try await remover.finalize(held)

    #expect(names("documents") == [])
  }

  @Test func aBookThatChangedSinceListedIsLeftAlone() async throws {
    try writeAliceAndMoby()
    let books = try await listing()
    let listed = try book("\(alice).azw3", in: books)
    try tree.write("\(alice).azw3", "another book")
    let documents = names("documents")

    await #expect(throws: KindleRemovalError.changedSinceListed) {
      try await USBKindleBookRemover().hold(listed, listedWith: books, on: tree.volume)
    }

    #expect(names("documents") == documents)
    #expect(exists(thumbnail) && exists(thumbnailTwin))
    #expect(!exists(holding))
  }

  @Test func aSymbolicLinkIsRefused() async throws {
    let target = try makeTemporaryDirectory().appending(path: "Dracula.pdf")
    let pdf = makePDF(title: "Dracula", author: nil)
    try pdf.write(to: target)
    let link = tree.documents.appending(path: "x.pdf")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let book = try Self.fixture(path: "x.pdf", for: target)

    await #expect(throws: KindleRemovalError.failed("documents/x.pdf isn't a book file")) {
      try await USBKindleBookRemover().hold(book, listedWith: [book], on: tree.volume)
    }

    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    #expect(try Data(contentsOf: target) == pdf)
  }

  @Test func aBookInALinkedFolderIsRefused() async throws {
    let outside = try makeTemporaryDirectory()
    let target = outside.appending(path: "x.pdf")
    try makePDF(title: "Dracula", author: nil).write(to: target)
    try FileManager.default.createSymbolicLink(
      at: tree.documents.appending(path: "A"), withDestinationURL: outside)
    let book = try Self.fixture(path: "A/x.pdf", for: target)

    await #expect(throws: KindleRemovalError.failed("Sendle won't delete documents/A/x.pdf")) {
      try await USBKindleBookRemover().hold(book, listedWith: [book], on: tree.volume)
    }

    #expect(FileManager.default.fileExists(atPath: target.path))
    #expect(!exists(holding))
  }

  @Test func aFailureMidHoldPutsBackWhatMoved() async throws {
    try writeAliceAndMoby()
    let books = try await listing()
    let documents = names("documents")
    let thumbnails = tree.root.appending(path: "system/thumbnails").path
    chmod(thumbnails, 0o555)
    defer { chmod(thumbnails, 0o755) }

    await #expect(throws: KindleRemovalError.failed("permission denied")) {
      try await USBKindleBookRemover().hold(
        book("\(alice).azw3", in: books), listedWith: books, on: tree.volume)
    }

    #expect(names("documents") == documents)
    #expect(exists(thumbnail) && exists(thumbnailTwin))
    #expect(!exists(holding))
  }

  @Test func undoRefusesWhenAFileTookItsPlace() async throws {
    try writeAliceAndMoby()
    let books = try await listing()
    let remover = USBKindleBookRemover()
    let held = try await remover.hold(
      book("\(alice).azw3", in: books), listedWith: books, on: tree.volume)
    try tree.write("\(alice).azw3", "a new book")

    await #expect(throws: KindleRemovalError.occupied("documents/\(alice).azw3")) {
      try await remover.restore(held)
    }
    #expect(names("\(holding)/\(held.id.uuidString)").count == 5)
    #expect(!exists("documents/\(alice).sdr"))

    try await remover.finalize(held)

    #expect(
      try String(contentsOf: tree.documents.appending(path: "\(alice).azw3"), encoding: .utf8)
        == "a new book")
    #expect(!exists(holding))
  }

  @Test func aFailedUndoKeepsTheBookHeld() async throws {
    try writeAliceAndMoby()
    let before = try contents(alicesFiles)
    let books = try await listing()
    let remover = USBKindleBookRemover()
    let held = try await remover.hold(
      book("\(alice).azw3", in: books), listedWith: books, on: tree.volume)
    chmod(tree.documents.path, 0o555)
    defer { chmod(tree.documents.path, 0o755) }

    await #expect(throws: KindleRemovalError.failed("permission denied")) {
      try await remover.restore(held)
    }
    #expect(names("\(holding)/\(held.id.uuidString)").count == 5)
    #expect(names("system/thumbnails") == [])

    chmod(tree.documents.path, 0o755)
    try await remover.restore(held)
    #expect(try contents(alicesFiles) == before)
  }

  @Test func leftoversFromBeforeAreCleared() async throws {
    try tree.writeRoot("\(holding)/old/0.held", "a book")

    #expect(await USBKindleBookRemover().clearLeftovers(on: tree.volume) == 1)
    #expect(!exists(holding))
    #expect(await USBKindleBookRemover().clearLeftovers(on: tree.volume) == 0)
  }

  @Test func clearingLeftoversKeepsWhatItHolds() async throws {
    try writeAliceAndMoby()
    let before = try contents(alicesFiles)
    let books = try await listing()
    let remover = USBKindleBookRemover()
    let held = try await remover.hold(
      book("\(alice).azw3", in: books), listedWith: books, on: tree.volume)

    #expect(await remover.clearLeftovers(on: tree.volume) == 0)

    try await remover.restore(held)
    #expect(try contents(alicesFiles) == before)
  }

  @Test func aLinkedHoldingFolderIsNeitherClearedNorUsed() async throws {
    try writeAliceAndMoby()
    let books = try await listing()
    let documents = names("documents")
    let target = try makeTemporaryDirectory()
    try Data("keep".utf8).write(to: target.appending(path: "keep.txt"))
    let link = tree.root.appending(path: holding)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let remover = USBKindleBookRemover()

    #expect(await remover.clearLeftovers(on: tree.volume) == 0)
    await #expect(throws: KindleRemovalError.failed("\(holding) isn't a folder")) {
      try await remover.hold(
        book("\(alice).azw3", in: books), listedWith: books, on: tree.volume)
    }

    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    #expect(try FileManager.default.contentsOfDirectory(atPath: target.path) == ["keep.txt"])
    #expect(try Data(contentsOf: target.appending(path: "keep.txt")) == Data("keep".utf8))
    #expect(names("documents") == documents)
  }

  @Test func finalizeNeverRemovesThroughALinkedHoldingFolder() async throws {
    try writeAliceAndMoby()
    let books = try await listing()
    let remover = USBKindleBookRemover()
    let held = try await remover.hold(
      book("\(alice).azw3", in: books), listedWith: books, on: tree.volume)
    let target = try makeTemporaryDirectory()
    let decoy = target.appending(path: "\(held.id.uuidString)/keep.txt")
    try FileManager.default.createDirectory(
      at: decoy.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: decoy)
    let link = tree.root.appending(path: holding)
    try FileManager.default.moveItem(at: link, to: tree.root.appending(path: "aside"))
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    await #expect(throws: KindleRemovalError.failed("\(holding) isn't a folder")) {
      try await remover.finalize(held)
    }

    #expect(try Data(contentsOf: decoy) == Data("keep".utf8))
  }

  @Test func aGoneKindleIsDisconnected() async throws {
    try writeAliceAndMoby()
    let books = try await listing()
    let listed = try book("\(alice).azw3", in: books)
    try FileManager.default.removeItem(at: tree.documents)

    await #expect(throws: KindleRemovalError.deviceDisconnected) {
      try await USBKindleBookRemover().hold(listed, listedWith: books, on: tree.volume)
    }
  }

  @Test func everyFolderAMoveOrRemovalTouchesIsFlushed() async throws {
    try writeAliceAndMoby()
    try tree.write("Abreu, Andrea/Panza.azw3", makeAZW3())
    let books = try await listing()
    let flushed = OSAllocatedUnfairLock<Set<String>>(initialState: [])
    let root = tree.root.path
    let remover = USBKindleBookRemover(
      log: NoActivityLog(),
      flush: { url in
        let path = String(url.path.dropFirst(root.count).drop { $0 == "/" })
        flushed.withLock { _ = $0.insert(path) }
      })
    func take() -> Set<String> {
      flushed.withLock {
        defer { $0 = [] }; return $0
      }
    }

    let alice = try await remover.hold(
      book("\(alice).azw3", in: books), listedWith: books, on: tree.volume)
    #expect(
      take().isSuperset(of: [
        "documents", "system/thumbnails", "\(holding)/\(alice.id.uuidString)", holding, "",
      ]))
    try await remover.restore(alice)
    #expect(take().isSuperset(of: ["documents", "system/thumbnails", ""]))

    let panza = try await remover.hold(
      book("Abreu, Andrea/Panza.azw3", in: books), listedWith: books, on: tree.volume)
    #expect(take().isSuperset(of: ["documents/Abreu, Andrea"]))
    try await remover.finalize(panza)
    #expect(take().isSuperset(of: ["documents", ""]))
  }

  /// A book as the listing would give it for the file at `target`.
  private static func fixture(path: String, for target: URL) throws -> KindleBook {
    let values = try target.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    return KindleBook.fixture(
      path: path, byteCount: Int64(try #require(values.fileSize)),
      modified: try #require(values.contentModificationDate))
  }
}
