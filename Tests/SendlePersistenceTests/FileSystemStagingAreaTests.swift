import Foundation
import SendleDomain
import SendlePersistence
import SendleTestSupport
import Testing

struct FileSystemStagingAreaTests {
  let base: URL
  let staging: FileSystemStagingArea

  init() throws {
    base = try makeTemporaryDirectory()
    staging = FileSystemStagingArea(
      root: base.appending(path: "staging", directoryHint: .isDirectory))
  }

  @Test func givesEachSendItsOwnFolder() throws {
    let first = try staging.makeDirectory()
    let second = try staging.makeDirectory()

    #expect(first != second)
    #expect(FileManager.default.fileExists(atPath: first.path()))
    #expect(FileManager.default.fileExists(atPath: second.path()))
  }

  @Test func writesAFileIntoAFolder() throws {
    let folder = try staging.makeDirectory()

    let file = try staging.writeFile(
      named: "Sendle test.txt", contents: Data("hi".utf8), in: folder)

    #expect(file.lastPathComponent == "Sendle test.txt")
    #expect(try Data(contentsOf: file) == Data("hi".utf8))
  }

  @Test func removesAFolderItCreated() throws {
    let folder = try staging.makeDirectory()

    staging.remove(folder)

    #expect(!FileManager.default.fileExists(atPath: folder.path()))
  }

  @Test func neverRemovesAnythingOutsideItsRoot() throws {
    let book = base.appending(path: "Books/Moby-Dick.epub", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: book, withIntermediateDirectories: true)
    let lookalike = base.appending(path: "staging-other", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: lookalike, withIntermediateDirectories: true)

    staging.remove(book)
    staging.remove(lookalike)
    staging.remove(staging.root)
    staging.remove(staging.root.appending(path: "../Books/Moby-Dick.epub"))

    #expect(FileManager.default.fileExists(atPath: book.path()))
    #expect(FileManager.default.fileExists(atPath: lookalike.path()))
  }

  @Test func purgeClearsLeftoversFromAnInterruptedSend() throws {
    let folder = try staging.makeDirectory()

    staging.purge()

    #expect(!FileManager.default.fileExists(atPath: folder.path()))
  }
}
