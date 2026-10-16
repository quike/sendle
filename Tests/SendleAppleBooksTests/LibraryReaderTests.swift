import Foundation
import SendleAppleBooks
import SendleDomain
import SendleTestSupport
import Testing

struct LibraryReaderTests {
  let folder: URL
  let scratch: URL
  let reader: LibraryReader

  init() throws {
    folder = try makeTemporaryDirectory()
    scratch = try makeTemporaryDirectory()
    reader = LibraryReader(scratchDirectory: scratch)
  }

  @Test func readsEveryColumnSendleUses() throws {
    let fixture = try LibraryDatabaseFixture(in: folder)
    try fixture.insert(
      .init(
        assetID: "A1", title: "Moby-Dick", author: "Herman Melville",
        path: "/Books/Moby-Dick.epub", language: "en", storeID: "123",
        creationDate: 700_000_000.5, contentType: 3, state: 2, fileSize: 42))

    let records = try reader.records(in: fixture.url)

    #expect(records.count == 1)
    let record = try #require(records.first)
    #expect(record.assetID == "A1")
    #expect(record.title == "Moby-Dick")
    #expect(record.author == "Herman Melville")
    #expect(record.path == "/Books/Moby-Dick.epub")
    #expect(record.language == "en")
    #expect(record.storeID == "123")
    #expect(record.creationDate == 700_000_000.5)
    #expect(record.contentType == 3)
    #expect(record.state == 2)
    #expect(record.fileSize == 42)
  }

  @Test func leavesOutSamplesHiddenBooksSeriesAndRowsWithoutAPath() throws {
    let fixture = try LibraryDatabaseFixture(in: folder)
    try fixture.insert(
      .init(assetID: "book"),
      .init(assetID: "sample", isSample: 1),
      .init(assetID: "hidden", isHidden: 1),
      .init(assetID: "series", contentType: 5),
      .init(assetID: "no-path", path: nil),
      .init(assetID: "empty-path", path: ""),
      .init(assetID: nil),
      .init(assetID: "null-flags", isHidden: nil, isSample: nil)
    )

    let ids = try reader.records(in: fixture.url).map(\.assetID).sorted()

    #expect(ids == ["book", "null-flags"])
  }

  @Test func readsNullOptionalColumnsAsNil() throws {
    let fixture = try LibraryDatabaseFixture(in: folder)
    try fixture.insert(
      .init(
        title: nil, author: nil, language: nil, creationDate: nil, contentType: nil, state: nil,
        fileSize: nil))

    let record = try #require(try reader.records(in: fixture.url).first)

    #expect(record.title == nil)
    #expect(record.author == nil)
    #expect(record.language == nil)
    #expect(record.creationDate == nil)
    #expect(record.contentType == nil)
    #expect(record.state == nil)
    #expect(record.fileSize == nil)
  }

  @Test func degradesWhenOptionalColumnsAreMissing() throws {
    let optional: Set = [
      "ZTITLE", "ZAUTHOR", "ZLANGUAGE", "ZSTOREID", "ZCREATIONDATE", "ZCONTENTTYPE", "ZISHIDDEN",
      "ZISSAMPLE", "ZSTATE", "ZFILESIZE",
    ]
    let fixture = try LibraryDatabaseFixture(in: folder, omitting: optional)
    try fixture.insert(.init(assetID: "A1", path: "/Books/Moby-Dick.epub"))

    let records = try reader.records(in: fixture.url)

    #expect(records.map(\.assetID) == ["A1"])
    #expect(records.first?.title == nil)
    #expect(records.first?.contentType == nil)
  }

  @Test func reportsMissingRequiredColumns() throws {
    let fixture = try LibraryDatabaseFixture(in: folder, omitting: ["ZPATH"])

    #expect(throws: LibraryError.unsupportedSchema(missingColumns: ["ZPATH"])) {
      try reader.records(in: fixture.url)
    }
  }

  @Test func reportsADatabaseWithoutTheAssetTableAsUnsupported() throws {
    let fixture = try LibraryDatabaseFixture(in: folder, withTable: false)

    #expect(throws: LibraryError.unsupportedSchema(missingColumns: ["ZASSETID", "ZPATH"])) {
      try reader.records(in: fixture.url)
    }
  }

  @Test func readsAPrivateCopyWhenTheDatabaseCannotBeOpenedReadOnly() throws {
    let fixture = try LibraryDatabaseFixture(in: folder)
    try fixture.insert(.init(assetID: "A1"))
    try fixture.closeAndRemoveSideFiles()

    let records = try reader.records(in: fixture.url)

    #expect(records.map(\.assetID) == ["A1"])
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: scratch.path(percentEncoded: false))
        .isEmpty)
  }

  @Test func readsRowsThatOnlyTheWALHoldsThroughTheCopy() throws {
    let fixture = try LibraryDatabaseFixture(in: folder)
    try fixture.insert(.init(assetID: "A1"))
    let locked = try makeTemporaryDirectory()
    let database = locked.appending(path: fixture.url.lastPathComponent)
    try FileManager.default.copyItem(at: fixture.url, to: database)
    try FileManager.default.copyItem(
      at: fixture.walURL, to: URL(filePath: database.path(percentEncoded: false) + "-wal"))
    let path = locked.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }

    #expect(try reader.records(in: database).map(\.assetID) == ["A1"])
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: scratch.path(percentEncoded: false))
        .isEmpty)
  }

  @Test func reportsAccessDeniedWhenTheDatabaseCannotBeRead() throws {
    let fixture = try LibraryDatabaseFixture(in: folder)
    try fixture.insert(.init())
    let path = fixture.url.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

    #expect(throws: LibraryError.accessDenied) { try reader.records(in: fixture.url) }
  }

  @Test(arguments: [false, true])
  func neverChangesBooksFiles(sideFilesRemoved: Bool) throws {
    let fixture = try LibraryDatabaseFixture(in: folder)
    try fixture.insert(.init(assetID: "A1"))
    if sideFilesRemoved { try fixture.closeAndRemoveSideFiles() }
    let before = try snapshot(of: folder, skipping: "-shm")

    _ = try reader.records(in: fixture.url)

    #expect(try snapshot(of: folder, skipping: "-shm") == before)
  }

  /// Every file name in `folder` with its bytes. The `-shm` index is skipped: it is shared memory
  /// that every reader, Books included, updates.
  private func snapshot(of folder: URL, skipping suffix: String) throws -> [String: Data] {
    var files: [String: Data] = [:]
    for name in try FileManager.default.contentsOfDirectory(
      atPath: folder.path(percentEncoded: false))
    {
      files[name] =
        name.hasSuffix(suffix) ? Data() : try Data(contentsOf: folder.appending(path: name))
    }
    return files
  }
}
