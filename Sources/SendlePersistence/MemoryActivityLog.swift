import Foundation
import SendleDomain
import os

/// The newest log lines, in memory only, so quitting Sendle clears them. Each line also goes to
/// the macOS log, with its text kept private there.
public final class MemoryActivityLog: ActivityLog, ActivityLogFeed {
  private struct State {
    var entries: [LogEntry] = []
    var nextID = 1
    var listeners: [UUID: AsyncStream<Void>.Continuation] = [:]
  }

  private static let loggers = Dictionary(
    uniqueKeysWithValues: LogArea.allCases.map {
      ($0, Logger(subsystem: "io.github.quike.Sendle", category: $0.rawValue))
    })

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let capacity: Int
  private let now: @Sendable () -> Date

  public init(capacity: Int = 5_000, now: @escaping @Sendable () -> Date = { Date() }) {
    self.capacity = max(capacity, 1)
    self.now = now
  }

  public func record(_ level: LogLevel, _ area: LogArea, _ message: String, heading: LogSubject?) {
    Self.loggers[area]?.log(level: level.osLogType, "\(message, privacy: .private)")
    let date = now()
    let listeners = state.withLock { state in
      state.entries.append(
        LogEntry(
          id: state.nextID, date: date, level: level, area: area, message: message,
          heading: heading))
      state.nextID += 1
      if state.entries.count > capacity {
        state.entries.removeFirst(state.entries.count - capacity)
      }
      return Array(state.listeners.values)
    }
    for listener in listeners { listener.yield() }
  }

  public func entries() -> [LogEntry] {
    state.withLock { $0.entries }
  }

  public func changes() -> AsyncStream<Void> {
    let (stream, continuation) = AsyncStream.makeStream(
      of: Void.self, bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    state.withLock { $0.listeners[id] = continuation }
    continuation.onTermination = { [weak self] _ in
      _ = self?.state.withLock { $0.listeners.removeValue(forKey: id) }
    }
    return stream
  }

  public func clear() {
    let listeners = state.withLock { state in
      state.entries = []
      return Array(state.listeners.values)
    }
    for listener in listeners { listener.yield() }
  }
}

extension LogLevel {
  fileprivate var osLogType: OSLogType {
    switch self {
    case .debug: .debug
    case .info: .info
    case .warning: .default
    case .error: .error
    }
  }
}
