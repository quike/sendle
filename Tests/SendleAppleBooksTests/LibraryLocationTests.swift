import Foundation
import SendleAppleBooks
import SendleDomain
import SendleTestSupport
import Testing

struct LibraryLocationTests {
  let folder: URL

  init() throws {
    folder = try makeTemporaryDirectory()
  }

  @Test func usesBooksContainerByDefault() {
    let location = LibraryLocation.standard(environment: [:])

    #expect(
      location
        == .directory(
          URL.homeDirectory.appending(
            path: "Library/Containers/com.apple.iBooksX/Data/Documents/BKLibrary",
            directoryHint: .isDirectory)))
  }

  @Test func usesTheDatabaseNamedBySENDLE_LIBRARY_DB() {
    let location = LibraryLocation.standard(environment: [
      "SENDLE_LIBRARY_DB": "/tmp/fixture.sqlite"
    ])

    #expect(location == .file(URL(filePath: "/tmp/fixture.sqlite")))
  }

  @Test func ignoresAnEmptyOverride() {
    #expect(
      LibraryLocation.standard(environment: ["SENDLE_LIBRARY_DB": ""]) != .file(URL(filePath: "")))
  }

  @Test func picksTheNewestLibraryDatabase() throws {
    let old = try touch("BKLibrary-1-091020131601.sqlite", modified: 1_000)
    let new = try touch("BKLibrary-1-202410151200.sqlite", modified: 2_000)
    _ = try touch("BKLibrary-1-202410151200.sqlite-wal", modified: 3_000)
    _ = try touch("BKSeriesDatabase-1.sqlite", modified: 4_000)

    #expect(try LibraryLocation.directory(folder).databaseURL().lastPathComponent == new)
    #expect(old != new)
  }

  @Test func reportsAFolderWithoutALibraryAsNotFound() throws {
    _ = try touch("notes.txt", modified: 1_000)

    #expect(throws: LibraryError.notFound) { try LibraryLocation.directory(folder).databaseURL() }
  }

  @Test func reportsAMissingFolderOrFileAsNotFound() {
    let missing = folder.appending(path: "missing", directoryHint: .isDirectory)

    #expect(throws: LibraryError.notFound) { try LibraryLocation.directory(missing).databaseURL() }
    #expect(throws: LibraryError.notFound) {
      try LibraryLocation.file(missing.appending(path: "BKLibrary.sqlite")).databaseURL()
    }
  }

  @Test func reportsAnUnreadableFolderAsAccessDenied() throws {
    let path = folder.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }

    #expect(throws: LibraryError.accessDenied) {
      try LibraryLocation.directory(folder).databaseURL()
    }
  }

  @Test func watchesOnlyLibraryFiles() {
    let directory = LibraryLocation.directory(folder).watched
    let file = LibraryLocation.file(folder.appending(path: "fixture.sqlite")).watched

    #expect(directory.directory == folder)
    #expect(directory.isLibraryFile("BKLibrary-1-1.sqlite"))
    #expect(directory.isLibraryFile("BKLibrary-1-1.sqlite-wal"))
    #expect(!directory.isLibraryFile("BKLibrary-1-1.sqlite-shm"))
    #expect(!directory.isLibraryFile("BKSeries-1.sqlite"))
    #expect(file.directory.standardizedFileURL == folder.standardizedFileURL)
    #expect(file.isLibraryFile("fixture.sqlite"))
    #expect(file.isLibraryFile("fixture.sqlite-wal"))
    #expect(!file.isLibraryFile("other.sqlite"))
  }

  private func touch(_ name: String, modified: TimeInterval) throws -> String {
    let url = folder.appending(path: name)
    try Data().write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: modified)],
      ofItemAtPath: url.path(percentEncoded: false))
    return name
  }
}
