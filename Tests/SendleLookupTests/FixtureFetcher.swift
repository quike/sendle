import Foundation
import SendleDomain
import SendleLookup
import Testing
import os

/// Answers each URL it was given from a recorded file under `Fixtures/`, and records what was
/// asked. An URL it wasn't given fails the test.
struct FixtureFetcher: HTTPFetching {
  private let replies: [String: (status: Int, file: String)]
  private let asked = OSAllocatedUnfairLock<[String]>(initialState: [])

  init(_ replies: [String: (Int, String)]) {
    self.replies = replies.mapValues { (status: $0.0, file: $0.1) }
  }

  /// The URLs in the order they were asked.
  var requests: [String] { asked.withLock { $0 } }

  func get(_ url: URL) async throws(LookupError) -> HTTPReply {
    asked.withLock { $0.append(url.absoluteString) }
    guard let reply = replies[url.absoluteString] else {
      Issue.record("Unexpected request: \(url.absoluteString)")
      throw .unreadable
    }
    return HTTPReply(status: reply.status, data: try Self.fixture(reply.file))
  }

  static func fixture(_ file: String) throws(LookupError) -> Data {
    guard
      let url = Bundle.module.resourceURL?.appendingPathComponent("Fixtures/\(file)"),
      let data = try? Data(contentsOf: url)
    else {
      Issue.record("Missing fixture: \(file)")
      throw .unreadable
    }
    return data
  }
}
