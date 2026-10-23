import Foundation
import SMTPKit
import os

/// A server that answers each read with the next scripted reply and records what it was sent.
public final class ScriptedSMTPTransport: SMTPTransport {
  public enum Read: Sendable {
    case reply(SMTPReply)
    case fail(SMTPTransportError)
    /// Waits until the reading task is cancelled.
    case hang
  }

  public enum Event: Hashable, Sendable {
    case open
    case write(String, timeout: Duration)
    case read(timeout: Duration)
    case upgradeToTLS
    case close
  }

  private struct State {
    var reads: [Read]
    var events: [Event] = []
    var writes = 0
  }

  private let state: OSAllocatedUnfairLock<State>
  private let failingWrite: (index: Int, error: SMTPTransportError)?
  private let hanging = Signal()

  /// `failingWrite` makes the write with that zero-based index fail.
  public init(_ reads: [Read], failingWrite: (index: Int, error: SMTPTransportError)? = nil) {
    state = OSAllocatedUnfairLock(initialState: State(reads: reads))
    self.failingWrite = failingWrite
  }

  public var events: [Event] { state.withLock { $0.events } }

  /// Everything written, in order, without timeouts.
  public var written: [String] {
    events.compactMap { if case .write(let text, _) = $0 { text } else { nil } }
  }

  public func waitUntilHanging() async {
    await hanging.wait()
  }

  public func open() async throws(SMTPTransportError) {
    record(.open)
  }

  public func readReply(timeout: Duration) async throws(SMTPTransportError) -> SMTPReply {
    let next = state.withLock { state -> Read in
      state.events.append(.read(timeout: timeout))
      return state.reads.isEmpty ? .fail(.closed) : state.reads.removeFirst()
    }
    switch next {
    case .reply(let reply): return reply
    case .fail(let error): throw error
    case .hang:
      await hanging.fire()
      try? await Task.sleep(for: .seconds(3_600))
      throw .cancelled
    }
  }

  public func write(_ data: Data, timeout: Duration) async throws(SMTPTransportError) {
    let index = state.withLock { state in
      state.events.append(.write(String(decoding: data, as: UTF8.self), timeout: timeout))
      defer { state.writes += 1 }
      return state.writes
    }
    if let failingWrite, failingWrite.index == index { throw failingWrite.error }
  }

  public func upgradeToTLS() async throws(SMTPTransportError) {
    record(.upgradeToTLS)
  }

  public func close() async {
    record(.close)
  }

  private func record(_ event: Event) {
    state.withLock { $0.events.append(event) }
  }
}

extension ScriptedSMTPTransport.Read {
  public static func code(_ code: Int, _ lines: String...) -> Self {
    .reply(SMTPReply(code: code, lines: lines.isEmpty ? [""] : lines))
  }
}
