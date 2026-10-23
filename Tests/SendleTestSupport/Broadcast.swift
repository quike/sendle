import Foundation
import os

/// Gives every subscriber its own stream, as the domain's stream ports promise, and sends each
/// value to all of them.
public final class Broadcast<Element: Sendable>: Sendable {
  private let subscribers = OSAllocatedUnfairLock<[UUID: AsyncStream<Element>.Continuation]>(
    initialState: [:])

  public init() {}

  public var subscriberCount: Int { subscribers.withLock { $0.count } }

  public func stream(startingWith first: Element? = nil) -> AsyncStream<Element> {
    let (stream, continuation) = AsyncStream.makeStream(of: Element.self)
    let id = UUID()
    subscribers.withLock { $0[id] = continuation }
    continuation.onTermination = { [weak self] _ in
      _ = self?.subscribers.withLock { $0.removeValue(forKey: id) }
    }
    if let first { continuation.yield(first) }
    return stream
  }

  public func send(_ value: Element) {
    for continuation in subscribers.withLock({ Array($0.values) }) {
      continuation.yield(value)
    }
  }

  public func finish() {
    for continuation in subscribers.withLock({ Array($0.values) }) {
      continuation.finish()
    }
  }
}
