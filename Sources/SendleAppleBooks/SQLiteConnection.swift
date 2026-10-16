import Foundation
import SQLite3

package struct SQLiteError: Error, Hashable, Sendable {
  package let code: Int32
  package let message: String
}

/// A database connection, closed when the last reference goes away.
package final class SQLiteConnection {
  private let handle: OpaquePointer

  package init(url: URL, readOnly: Bool) throws(SQLiteError) {
    var handle: OpaquePointer?
    let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
    let code = sqlite3_open_v2(url.path(percentEncoded: false), &handle, flags, nil)
    guard code == SQLITE_OK, let handle else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
      sqlite3_close_v2(handle)
      throw SQLiteError(code: code, message: message)
    }
    self.handle = handle
    sqlite3_busy_timeout(handle, 2_000)
  }

  deinit {
    sqlite3_close_v2(handle)
  }

  /// The column names of `table`; empty when the table doesn't exist.
  package func columns(of table: String) throws(SQLiteError) -> [String] {
    try rows("SELECT name FROM pragma_table_info(?1)", bindings: [table]) { $0.string(0) ?? "" }
  }

  package func rows<Row>(
    _ sql: String,
    bindings: [String] = [],
    _ makeRow: (SQLiteRow) -> Row
  ) throws(SQLiteError) -> [Row] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw lastError()
    }
    defer { sqlite3_finalize(statement) }
    for (index, value) in bindings.enumerated() {
      sqlite3_bind_text(statement, Int32(index + 1), value, -1, sqliteTransient)
    }
    var result: [Row] = []
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW: result.append(makeRow(SQLiteRow(statement: statement)))
      case SQLITE_DONE: return result
      default: throw lastError()
      }
    }
  }

  package func execute(_ sql: String) throws(SQLiteError) {
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
  }

  private func lastError() -> SQLiteError {
    SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
  }
}

/// One result row, valid only inside the closure that receives it.
package struct SQLiteRow {
  fileprivate let statement: OpaquePointer

  package func string(_ column: Int32) -> String? {
    guard let text = sqlite3_column_text(statement, column) else { return nil }
    return String(cString: text)
  }

  package func int64(_ column: Int32) -> Int64? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
    return sqlite3_column_int64(statement, column)
  }

  package func double(_ column: Int32) -> Double? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
    return sqlite3_column_double(statement, column)
  }
}

/// SQLite copies bound text before `bind` returns.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
