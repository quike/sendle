import Foundation
import SendleDomain
import os

/// Answers from what it was given and records every request. An ISBN it wasn't given finds
/// nothing; an image it wasn't given is refused.
public final class FakeCatalogue: BookCatalogue {
  private struct Requests {
    var asked: [String] = []
    var cancelled: [String] = []
  }

  public let source: LookupSource
  private let byISBN: [String: Result<FoundEdition?, LookupError>]
  private let byTitle: Result<[FoundEdition], LookupError>
  private let images: [URL: Data]
  /// While set, a request is recorded and then waits for it to fire, or for its task to be
  /// cancelled, before answering.
  private let gate: Signal?
  private let recorded = OSAllocatedUnfairLock(initialState: Requests())

  public init(
    _ source: LookupSource,
    byISBN: [String: Result<FoundEdition?, LookupError>] = [:],
    byTitle: Result<[FoundEdition], LookupError> = .success([]),
    images: [URL: Data] = [:],
    gate: Signal? = nil
  ) {
    self.source = source
    self.byISBN = byISBN
    self.byTitle = byTitle
    self.images = images
    self.gate = gate
  }

  /// "isbn:<isbn>" or "title:<title>|<author>|<language>", in the order they were asked.
  public var requests: [String] { recorded.withLock { $0.asked } }

  /// The requests whose task was cancelled while they waited for the gate.
  public var cancelledRequests: [String] { recorded.withLock { $0.cancelled } }

  public func edition(isbn: String) async throws(LookupError) -> FoundEdition? {
    await ask("isbn:\(isbn)")
    return try (byISBN[isbn] ?? .success(nil)).get()
  }

  public func editions(title: String, author: String?, language: String?) async throws(LookupError)
    -> [FoundEdition]
  {
    await ask("title:\(title)|\(author ?? "")|\(language ?? "")")
    return try byTitle.get()
  }

  public func image(at url: URL) async throws(LookupError) -> Data? {
    guard let data = images[url] else { throw .refused(status: 404) }
    return data
  }

  private func ask(_ request: String) async {
    recorded.withLock { $0.asked.append(request) }
    if let gate, await !gate.waitUnlessCancelled() {
      recorded.withLock { $0.cancelled.append(request) }
    }
  }
}

extension FoundEdition {
  public static func fixture(
    _ source: LookupSource = .openLibrary,
    title: String? = "Los ritos del agua",
    author: String? = "Eva García Sáenz",
    year: String? = "2017",
    isbn: String? = "9788408172277",
    language: String? = "es"
  ) -> FoundEdition {
    FoundEdition(
      source: source, title: title, author: author, year: year, isbn: isbn, language: language)
  }
}
