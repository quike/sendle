import Foundation
import SendleAppleBooks

/// A Books-style library database (the Books 8.5 `ZBKLIBRARYASSET` subset) in WAL mode.
/// The writer stays open, like Books while it runs, so new rows live in the `-wal` file.
final class LibraryDatabaseFixture {
  struct Asset {
    var assetID: String? = UUID().uuidString
    var title: String? = "Moby-Dick"
    var author: String? = "Herman Melville"
    var path: String? = "/Books/Moby-Dick.epub"
    var language: String? = "en"
    var storeID: String?
    var creationDate: Double? = 700_000_000
    var contentType: Int? = 1
    var isHidden: Int? = 0
    var isSample: Int? = 0
    var state: Int? = 1
    var fileSize: Int? = 0
  }

  static let columns: [(name: String, type: String)] = [
    ("ZASSETID", "VARCHAR"), ("ZTITLE", "VARCHAR"), ("ZAUTHOR", "VARCHAR"), ("ZPATH", "VARCHAR"),
    ("ZLANGUAGE", "VARCHAR"), ("ZSTOREID", "VARCHAR"), ("ZCREATIONDATE", "TIMESTAMP"),
    ("ZCONTENTTYPE", "INTEGER"), ("ZISHIDDEN", "INTEGER"), ("ZISSAMPLE", "INTEGER"),
    ("ZSTATE", "INTEGER"), ("ZFILESIZE", "INTEGER"), ("ZSORTTITLE", "VARCHAR"),
  ]

  let url: URL
  private let present: [String]
  private var writer: SQLiteConnection?

  init(
    in directory: URL,
    name: String = "BKLibrary-1-091020131601.sqlite",
    omitting omitted: Set<String> = [],
    withTable: Bool = true
  ) throws {
    url = directory.appending(path: name)
    present = Self.columns.map(\.name).filter { !omitted.contains($0) }
    let writer = try SQLiteConnection(url: url, readOnly: false)
    try writer.execute("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;")
    if withTable {
      let definitions = Self.columns.filter { present.contains($0.name) }.map {
        "\($0.name) \($0.type)"
      }
      try writer.execute(
        "CREATE TABLE ZBKLIBRARYASSET (Z_PK INTEGER PRIMARY KEY, "
          + definitions.joined(separator: ", ") + ")")
    } else {
      try writer.execute("CREATE TABLE ZOTHER (Z_PK INTEGER PRIMARY KEY)")
    }
    self.writer = writer
  }

  var walURL: URL { URL(filePath: url.path(percentEncoded: false) + "-wal") }

  func insert(_ assets: Asset...) throws {
    guard let writer else { return }
    for asset in assets {
      let values: [String: String] = [
        "ZASSETID": literal(asset.assetID), "ZTITLE": literal(asset.title),
        "ZAUTHOR": literal(asset.author), "ZPATH": literal(asset.path),
        "ZLANGUAGE": literal(asset.language), "ZSTOREID": literal(asset.storeID),
        "ZCREATIONDATE": literal(asset.creationDate), "ZCONTENTTYPE": literal(asset.contentType),
        "ZISHIDDEN": literal(asset.isHidden), "ZISSAMPLE": literal(asset.isSample),
        "ZSTATE": literal(asset.state), "ZFILESIZE": literal(asset.fileSize),
        "ZSORTTITLE": literal(asset.title),
      ]
      let names = present.filter { values[$0] != nil }
      try writer.execute(
        "INSERT INTO ZBKLIBRARYASSET (\(names.joined(separator: ", "))) VALUES ("
          + names.compactMap { values[$0] }.joined(separator: ", ") + ")")
    }
  }

  /// Checkpoints, closes the writer and deletes the `-wal` and `-shm` files, as after Books quits.
  /// A read-only connection can't open a WAL database in that state.
  func closeAndRemoveSideFiles() throws {
    try writer?.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    writer = nil
    for suffix in ["-wal", "-shm"] {
      try? FileManager.default.removeItem(atPath: url.path(percentEncoded: false) + suffix)
    }
  }

  private func literal(_ text: String?) -> String {
    guard let text else { return "NULL" }
    return "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
  }

  private func literal(_ number: Int?) -> String {
    number.map(String.init) ?? "NULL"
  }

  private func literal(_ number: Double?) -> String {
    number.map { String($0) } ?? "NULL"
  }
}
