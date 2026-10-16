import Foundation
import SendleAppleBooks
import SendleTestSupport
import Testing

struct SQLiteConnectionTests {
  let folder: URL
  let fixture: LibraryDatabaseFixture

  init() throws {
    folder = try makeTemporaryDirectory()
    fixture = try LibraryDatabaseFixture(in: folder)
  }

  @Test func readsRowsTheWriterHasNotCheckpointedYet() throws {
    try fixture.insert(.init(title: "Moby-Dick"), .init(title: "Dracula"))

    let reader = try SQLiteConnection(url: fixture.url, readOnly: true)
    let titles = try reader.rows("SELECT ZTITLE FROM ZBKLIBRARYASSET ORDER BY ZTITLE") {
      $0.string(0)
    }

    #expect(titles == ["Dracula", "Moby-Dick"])
    let walSize =
      try FileManager.default.attributesOfItem(
        atPath: fixture.walURL.path(percentEncoded: false))[.size] as? Int
    #expect((walSize ?? 0) > 0)
  }

  @Test func readsNullsAsNil() throws {
    try fixture.insert(.init(author: nil, creationDate: nil, contentType: nil))

    let reader = try SQLiteConnection(url: fixture.url, readOnly: true)
    let row = try #require(
      try reader.rows("SELECT ZAUTHOR, ZCREATIONDATE, ZCONTENTTYPE FROM ZBKLIBRARYASSET") {
        [$0.string(0) as Any?, $0.double(1) as Any?, $0.int64(2) as Any?]
      }.first)

    #expect(row.allSatisfy { $0 == nil })
  }

  @Test func listsTheColumnsOfATable() throws {
    let reader = try SQLiteConnection(url: fixture.url, readOnly: true)

    #expect(try reader.columns(of: "ZBKLIBRARYASSET").contains("ZASSETID"))
    #expect(try reader.columns(of: "ZNOSUCHTABLE").isEmpty)
  }

  @Test func refusesToOpenAMissingFileReadOnly() {
    #expect(throws: SQLiteError.self) {
      try SQLiteConnection(url: folder.appending(path: "nothing.sqlite"), readOnly: true)
    }
    #expect(
      !FileManager.default.fileExists(
        atPath: folder.appending(path: "nothing.sqlite").path(percentEncoded: false)))
  }
}
