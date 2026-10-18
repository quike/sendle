import Foundation

public enum LogLevel: Int, Hashable, Sendable, CaseIterable, Comparable {
  case debug
  case info
  case warning
  case error

  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// What part of Sendle a log line comes from.
public enum LogArea: String, Hashable, Sendable, CaseIterable {
  case mail
  case boko
  case usb
  case library
  case epub
  /// Sendle's own housekeeping: settings, the Keychain, launch at login.
  case app

  public var tag: String {
    switch self {
    case .mail: "MAIL"
    case .boko: "BOKO"
    case .usb: "USB"
    case .library: "LIB"
    case .epub: "EPUB"
    case .app: "APP"
    }
  }
}

/// A send whose story starts at a heading line: one book, or a Send test.
public enum LogSubject: Hashable, Sendable {
  case book(BookID)
  case sendTest
}

public struct LogEntry: Hashable, Sendable, Identifiable {
  /// Counts up from 1 in the order the lines were recorded.
  public let id: Int
  public let date: Date
  public let level: LogLevel
  public let area: LogArea
  /// One line or several, such as a server's multi-line reply.
  public let message: String
  /// Set on the line that opens a send's story.
  public let heading: LogSubject?

  public init(
    id: Int, date: Date, level: LogLevel, area: LogArea, message: String,
    heading: LogSubject? = nil
  ) {
    self.id = id
    self.date = date
    self.level = level
    self.area = area
    self.message = message
    self.heading = heading
  }
}

/// Where Sendle tells what it does underneath. It must never be given a password.
public protocol ActivityLog: Sendable {
  func record(_ level: LogLevel, _ area: LogArea, _ message: String, heading: LogSubject?)
}

extension ActivityLog {
  public func debug(_ area: LogArea, _ message: String) {
    record(.debug, area, message, heading: nil)
  }

  public func info(_ area: LogArea, _ message: String) {
    record(.info, area, message, heading: nil)
  }

  public func warning(_ area: LogArea, _ message: String) {
    record(.warning, area, message, heading: nil)
  }

  public func error(_ area: LogArea, _ message: String) {
    record(.error, area, message, heading: nil)
  }

  /// Opens the story of a send, so the logs screen can show where it starts.
  public func heading(_ subject: LogSubject, _ area: LogArea, _ message: String) {
    record(.info, area, message, heading: subject)
  }
}

/// Records nothing, for code that runs without a log.
public struct NoActivityLog: ActivityLog {
  public init() {}

  public func record(_ level: LogLevel, _ area: LogArea, _ message: String, heading: LogSubject?) {}
}

/// The recorded lines, for the logs screen.
public protocol ActivityLogFeed: Sendable {
  /// Oldest first.
  func entries() -> [LogEntry]
  /// An independent stream per call that emits after each change.
  func changes() -> AsyncStream<Void>
  func clear()
}
