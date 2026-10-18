import Foundation
import SendleDomain
import os

/// A log that keeps every line, for tests to read back.
public final class FakeActivityLog: ActivityLog, ActivityLogFeed {
  private let lines = OSAllocatedUnfairLock<[LogEntry]>(initialState: [])
  private let broadcast = Broadcast<Void>()

  public init() {}

  public func record(_ level: LogLevel, _ area: LogArea, _ message: String, heading: LogSubject?) {
    lines.withLock {
      $0.append(
        LogEntry(
          id: $0.count + 1, date: Date(timeIntervalSince1970: 1_800_000_000), level: level,
          area: area, message: message, heading: heading))
    }
    broadcast.send(())
  }

  public func entries() -> [LogEntry] {
    lines.withLock { $0 }
  }

  public func changes() -> AsyncStream<Void> {
    broadcast.stream()
  }

  public func clear() {
    lines.withLock { $0 = [] }
    broadcast.send(())
  }

  /// "LEVEL AREA message" for each line, e.g. "error MAIL S: 553 …".
  public var summary: [String] {
    entries().map { "\($0.level) \($0.area.tag) \($0.message)" }
  }

  public func messages(in area: LogArea) -> [String] {
    entries().filter { $0.area == area }.map(\.message)
  }
}
