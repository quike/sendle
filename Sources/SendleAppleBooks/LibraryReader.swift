import Foundation
import SendleDomain
import os

private let logger = Logger(subsystem: "io.github.quike.Sendle", category: "apple-books")

/// One book row of Books' `ZBKLIBRARYASSET` table, as stored.
package struct AssetRecord: Hashable, Sendable {
  package var assetID: String
  package var title: String?
  package var author: String?
  package var path: String
  package var language: String?
  package var storeID: String?
  package var creationDate: Double?
  package var contentType: Int64?
  package var state: Int64?
  package var fileSize: Int64?
}

/// Reads the asset table without ever writing to Books' files.
package struct LibraryReader: Sendable {
  private let scratchDirectory: URL

  package init(scratchDirectory: URL = FileManager.default.temporaryDirectory) {
    self.scratchDirectory = scratchDirectory
  }

  /// Opens the database read-only while Books' `-wal` and `-shm` files are there. Otherwise, or
  /// when that open fails, reads a private copy: without them, some SQLite versions fail the open
  /// and others create the files, which would write into Books' folder.
  package func records(in database: URL) throws(LibraryError) -> [AssetRecord] {
    guard Self.hasSideFiles(database) else { return try readCopy(of: database) }
    do throws(ReadFailure) {
      return try Self.read(database, readOnly: true)
    } catch {
      switch error {
      case .missingColumns(let columns):
        throw .unsupportedSchema(missingColumns: columns)
      case .database(let failure):
        logger.notice("Read-only open failed (\(failure.code)); reading a copy")
        return try readCopy(of: database)
      }
    }
  }

  private func readCopy(of database: URL) throws(LibraryError) -> [AssetRecord] {
    let folder = scratchDirectory.appending(
      path: "Sendle-library-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: folder) }
    let copy = folder.appending(path: database.lastPathComponent)
    do {
      // WAL first: a checkpoint between the two reads then only repeats pages the copy has.
      let wal = Self.wal(of: database)
      let walBytes =
        FileManager.default.fileExists(atPath: wal.path(percentEncoded: false))
        ? try Data(contentsOf: wal) : nil
      let bytes = try Data(contentsOf: database)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try bytes.write(to: copy)
      try walBytes?.write(to: Self.wal(of: copy))
    } catch let error as CocoaError where error.code == .fileReadNoPermission {
      throw .accessDenied
    } catch {
      throw .unreadable(error.localizedDescription)
    }
    do throws(ReadFailure) {
      return try Self.read(copy, readOnly: false)
    } catch {
      switch error {
      case .missingColumns(let columns): throw .unsupportedSchema(missingColumns: columns)
      case .database(let failure): throw .unreadable(failure.message)
      }
    }
  }

  private enum ReadFailure: Error {
    case database(SQLiteError)
    case missingColumns([String])
  }

  private static func read(_ database: URL, readOnly: Bool) throws(ReadFailure) -> [AssetRecord] {
    let connection: SQLiteConnection
    let columns: [String]
    do throws(SQLiteError) {
      connection = try SQLiteConnection(url: database, readOnly: readOnly)
      columns = try connection.columns(of: AssetQuery.table)
    } catch {
      throw .database(error)
    }
    let query = AssetQuery(columns: columns)
    guard query.missingRequired.isEmpty else { throw .missingColumns(query.missingRequired) }
    if !query.missingOptional.isEmpty {
      logger.notice(
        "Books library lacks \(query.missingOptional.joined(separator: ", "), privacy: .public)")
    }
    do throws(SQLiteError) {
      return try connection.rows(query.sql, query.record)
    } catch {
      throw .database(error)
    }
  }

  private static func wal(of database: URL) -> URL {
    URL(filePath: database.path(percentEncoded: false) + "-wal")
  }

  private static func hasSideFiles(_ database: URL) -> Bool {
    ["-wal", "-shm"].allSatisfy {
      FileManager.default.fileExists(atPath: database.path(percentEncoded: false) + $0)
    }
  }
}

/// The SELECT for whichever columns this version of Books has. Missing optional columns read as
/// NULL, and their filters are skipped.
struct AssetQuery {
  static let table = "ZBKLIBRARYASSET"

  enum Column: String, CaseIterable {
    case assetID = "ZASSETID"
    case title = "ZTITLE"
    case author = "ZAUTHOR"
    case path = "ZPATH"
    case language = "ZLANGUAGE"
    case storeID = "ZSTOREID"
    case creationDate = "ZCREATIONDATE"
    case contentType = "ZCONTENTTYPE"
    case state = "ZSTATE"
    case fileSize = "ZFILESIZE"
    case isHidden = "ZISHIDDEN"
    case isSample = "ZISSAMPLE"

    static let required: [Column] = [.assetID, .path]
    /// Read into `AssetRecord`; the flags only filter.
    static let selected: [Column] = allCases.filter { $0 != .isHidden && $0 != .isSample }

    var index: Int32 { Int32(Self.selected.firstIndex(of: self) ?? 0) }
  }

  let missingRequired: [String]
  let missingOptional: [String]
  let sql: String

  init(columns: [String]) {
    let available = Set(columns.map { $0.uppercased() })
    let missing = Column.allCases.filter { !available.contains($0.rawValue) }
    missingRequired = missing.filter(Column.required.contains).map(\.rawValue)
    missingOptional = missing.filter { !Column.required.contains($0) }.map(\.rawValue)
    let list = Column.selected.map { available.contains($0.rawValue) ? $0.rawValue : "NULL" }
    var conditions = ["ZASSETID IS NOT NULL", "ZPATH IS NOT NULL", "ZPATH != ''"]
    if available.contains(Column.isSample.rawValue) {
      conditions.append("COALESCE(ZISSAMPLE, 0) = 0")
    }
    if available.contains(Column.isHidden.rawValue) {
      conditions.append("COALESCE(ZISHIDDEN, 0) = 0")
    }
    if available.contains(Column.contentType.rawValue) {
      conditions.append("ZCONTENTTYPE IS NOT 5")  // series containers, not books
    }
    sql =
      "SELECT \(list.joined(separator: ", ")) FROM \(Self.table) WHERE "
      + conditions.joined(separator: " AND ")
  }

  func record(_ row: SQLiteRow) -> AssetRecord {
    AssetRecord(
      assetID: row.string(Column.assetID.index) ?? "",
      title: row.string(Column.title.index),
      author: row.string(Column.author.index),
      path: row.string(Column.path.index) ?? "",
      language: row.string(Column.language.index),
      storeID: row.string(Column.storeID.index),
      creationDate: row.double(Column.creationDate.index),
      contentType: row.int64(Column.contentType.index),
      state: row.int64(Column.state.index),
      fileSize: row.int64(Column.fileSize.index)
    )
  }
}
