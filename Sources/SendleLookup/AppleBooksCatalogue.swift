import Foundation
import SendleDomain

/// Apple Books, through the iTunes Search API, which needs no key. It knows a book's title, author
/// and cover, and never its year, ISBN, language or publisher.
public struct AppleBooksCatalogue: BookCatalogue {
  public let source = LookupSource.appleBooks
  private let fetcher: any HTTPFetching
  private let storefront: String

  private static let site = "https://itunes.apple.com"

  public init(fetcher: any HTTPFetching, storefront: String) {
    self.fetcher = fetcher
    self.storefront = storefront
  }

  public func edition(isbn: String) async throws(LookupError) -> FoundEdition? {
    let url = try Self.url("lookup", [("isbn", isbn), ("country", storefront)])
    return try await ebooks(at: url).first.map(found)
  }

  /// Apple's search has no language to narrow by, so `language` is not used.
  public func editions(title: String, author: String?, language: String?) async throws(LookupError)
    -> [FoundEdition]
  {
    let term = [title, author].compactMap { $0 }.joined(separator: " ")
    let url = try Self.url(
      "search",
      [
        ("term", term), ("media", "ebook"), ("entity", "ebook"), ("limit", "10"),
        ("country", storefront),
      ])
    return try await ebooks(at: url).map(found)
  }

  public func image(at url: URL) async throws(LookupError) -> Data? {
    let reply = try await fetcher.get(url)
    return reply.status == 200 ? reply.data : nil
  }

  private static func url(
    _ endpoint: String, _ parameters: [(name: String, value: String)]
  ) throws(LookupError) -> URL {
    let query = parameters.map { "\($0.name)=\(queryEscaped($0.value))" }.joined(separator: "&")
    guard let url = URL(string: "\(site)/\(endpoint)?\(query)") else { throw .unreadable }
    return url
  }

  /// The ebooks in the answer at `url`, in the order Apple sent them.
  private func ebooks(at url: URL) async throws(LookupError) -> [Listing] {
    let reply = try await fetcher.get(url)
    guard reply.status == 200 else { throw .refused(status: reply.status) }
    do {
      return try JSONDecoder().decode(Answer.self, from: reply.data).results.filter {
        $0.kind == "ebook"
      }
    } catch {
      throw .unreadable
    }
  }

  private func found(_ listing: Listing) -> FoundEdition {
    FoundEdition(
      source: source,
      title: listing.trackName,
      author: listing.artistName,
      cover: listing.artworkUrl100.flatMap { Self.artwork($0, side: 3000) },
      thumbnail: listing.artworkUrl100.flatMap { Self.artwork($0, side: 200) },
      link: listing.trackViewUrl.flatMap { URL(string: $0) })
  }

  /// The artwork resized to fit a `side` × `side` box.
  private static func artwork(_ link: String, side: Int) -> URL? {
    URL(string: link.replacing("100x100bb", with: "\(side)x\(side)bb"))
  }
}

private struct Answer: Decodable {
  let results: [Listing]
}

private struct Listing: Decodable {
  let kind: String?
  let trackName: String?
  let artistName: String?
  let artworkUrl100: String?
  let trackViewUrl: String?
}
