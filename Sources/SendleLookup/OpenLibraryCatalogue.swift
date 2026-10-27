import Foundation
import SendleDomain

/// Open Library, which needs no key.
public struct OpenLibraryCatalogue: BookCatalogue {
  public let source = LookupSource.openLibrary
  private let fetcher: any HTTPFetching

  private static let site = "https://openlibrary.org"
  private static let covers = "https://covers.openlibrary.org/b/id"
  private static let worksSearched = 2
  private static let separator = " & "
  /// Open Library answers a missing cover with a one-pixel GIF.
  private static let smallestImage = 1_000

  public init(fetcher: any HTTPFetching) {
    self.fetcher = fetcher
  }

  public func edition(isbn: String) async throws(LookupError) -> FoundEdition? {
    let record: EditionRecord? = try await decoded(at: "\(Self.site)/isbn/\(isbn).json")
    guard let record else { return nil }
    let author = try await authors(of: record)
    return found(record, author: author, searched: isbn)
  }

  public func editions(title: String, author: String?, language: String?) async throws(LookupError)
    -> [FoundEdition]
  {
    let search: SearchRecord? = try await decoded(
      at: Self.searchURL(title: title, author: author, language: language))
    var editions: [FoundEdition] = []
    for work in (search?.docs ?? []).prefix(Self.worksSearched) {
      let page: EditionsRecord? = try await decoded(
        at: "\(Self.site)\(work.key)/editions.json?limit=50")
      let names = work.authorName?.joined(separator: Self.separator)
      editions += (page?.entries ?? []).map { found($0, author: names) }
    }
    return editions
  }

  public func image(at url: URL) async throws(LookupError) -> Data? {
    if let data = try await imageData(at: url) { return data }
    guard let large = Self.largeCover(of: url) else { return nil }
    return try await imageData(at: large)
  }

  private func imageData(at url: URL) async throws(LookupError) -> Data? {
    let reply = try await fetcher.get(url)
    switch reply.status {
    case 200: return reply.data.count >= Self.smallestImage ? reply.data : nil
    case 404: return nil
    default: throw .refused(status: reply.status)
    }
  }

  /// The large version of an original cover, `/b/id/{id}.jpg`.
  private static func largeCover(of url: URL) -> URL? {
    let id = url.deletingPathExtension().lastPathComponent
    guard url.absoluteString == "\(covers)/\(id).jpg" else { return nil }
    return URL(string: "\(covers)/\(id)-L.jpg?default=false")
  }

  private static func searchURL(title: String, author: String?, language: String?) -> String {
    var items = [URLQueryItem(name: "title", value: title)]
    if let author { items.append(URLQueryItem(name: "author", value: author)) }
    items.append(URLQueryItem(name: "limit", value: "5"))
    items.append(URLQueryItem(name: "fields", value: "key,title,author_name"))
    if let language { items.append(URLQueryItem(name: "lang", value: language)) }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "openlibrary.org"
    components.path = "/search.json"
    components.queryItems = items
    // URLComponents leaves "+" as it is, which the server reads as a space.
    let query = components.percentEncodedQuery
    components.percentEncodedQuery = query?.replacing("+", with: "%2B")
    return components.string ?? ""
  }

  private func found(
    _ record: EditionRecord, author: String?, searched: String? = nil
  ) -> FoundEdition {
    let cover = record.covers?.first { $0 != -1 }
    let isbns = (record.isbn13 ?? []) + (record.isbn10 ?? [])
    let language = record.languages?.first?.key.split(separator: "/").last
    return FoundEdition(
      source: source,
      title: record.title,
      author: author,
      year: record.publishDate.flatMap(firstYear),
      isbn: foundISBN(in: isbns, searched: searched),
      language: language.flatMap { MARCLanguages.bcp47(String($0)) },
      publisher: record.publishers?.first,
      cover: cover.flatMap { URL(string: "\(Self.covers)/\($0).jpg") },
      thumbnail: cover.flatMap { URL(string: "\(Self.covers)/\($0)-M.jpg?default=false") },
      link: URL(string: "\(Self.site)\(record.key)"))
  }

  /// The names of the edition's authors, or of its work's when the edition names none.
  private func authors(of edition: EditionRecord) async throws(LookupError) -> String? {
    var keys = (edition.authors ?? []).map(\.key)
    if keys.isEmpty, let work = edition.works?.first {
      let record: WorkRecord? = try await decoded(at: "\(Self.site)\(work.key).json")
      keys = (record?.authors ?? []).map(\.author.key)
    }
    var names: [String] = []
    for key in keys {
      let author: AuthorRecord? = try await decoded(at: "\(Self.site)\(key).json")
      if let name = author?.name { names.append(name) }
    }
    return names.isEmpty ? nil : names.joined(separator: Self.separator)
  }

  /// The JSON at `url`, or nil when Open Library has nothing there.
  private func decoded<Record: Decodable>(at url: String) async throws(LookupError) -> Record? {
    guard let url = URL(string: url) else { throw .unreadable }
    let reply = try await fetcher.get(url)
    switch reply.status {
    case 200:
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      do {
        return try decoder.decode(Record.self, from: reply.data)
      } catch {
        throw .unreadable
      }
    case 404: return nil
    default: throw .refused(status: reply.status)
    }
  }
}

private struct KeyRecord: Decodable {
  let key: String
}

private struct EditionRecord: Decodable {
  let key: String
  let title: String?
  let authors: [KeyRecord]?
  let works: [KeyRecord]?
  let publishDate: String?
  let isbn13: [String]?
  let isbn10: [String]?
  let languages: [KeyRecord]?
  let publishers: [String]?
  let covers: [Int]?
}

private struct EditionsRecord: Decodable {
  let entries: [EditionRecord]
}

private struct SearchRecord: Decodable {
  struct Work: Decodable {
    let key: String
    let authorName: [String]?
  }

  let docs: [Work]
}

private struct WorkRecord: Decodable {
  struct Role: Decodable {
    let author: KeyRecord
  }

  let authors: [Role]?
}

private struct AuthorRecord: Decodable {
  let name: String?
}
