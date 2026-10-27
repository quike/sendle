import Foundation
import ImageIO
import SendleDomain

/// Google Books, which answers only to the user's own API key.
public struct GoogleBooksCatalogue: BookCatalogue {
  public let source = LookupSource.googleBooks
  private let fetcher: any HTTPFetching
  private let keys: any SecretStore

  private static let site = "https://www.googleapis.com/books/v1/volumes"
  private static let separator = " & "
  /// The size of Google's "image not available" picture.
  private static let placeholder = (width: 128, height: 170)
  /// What Google sends for a language it doesn't know.
  private static let unknownLanguages: Set = ["", "und", "un", "zxx"]

  public init(fetcher: any HTTPFetching, keys: any SecretStore) {
    self.fetcher = fetcher
    self.keys = keys
  }

  public func edition(isbn: String) async throws(LookupError) -> FoundEdition? {
    let key = try await apiKey()
    let search: VolumeList? = try await decoded(
      at: Self.url(terms: ["isbn:\(isbn)"], parameters: [("key", key)]))
    guard let id = search?.items?.first?.id else { return nil }
    let volume: Volume? = try await decoded(
      at: Self.url(id: id, parameters: [("key", key)]), missingIsNil: true)
    return volume.map { found($0, searched: isbn) }
  }

  public func editions(title: String, author: String?, language: String?) async throws(LookupError)
    -> [FoundEdition]
  {
    let key = try await apiKey()
    var terms = [Self.phrase("intitle", title)]
    if let author { terms.append(Self.phrase("inauthor", author)) }
    var parameters = [("printType", "books"), ("maxResults", "10"), ("key", key)]
    if let language { parameters.append(("langRestrict", language)) }
    let search: VolumeList? = try await decoded(
      at: Self.url(terms: terms, parameters: parameters))
    return (search?.items ?? []).map { found($0) }
  }

  /// Nil for Google's "image not available" picture: a 128 × 170 PNG, or a banner as wide as it is
  /// tall or wider.
  public func image(at url: URL) async throws(LookupError) -> Data? {
    let reply = try await fetcher.get(url)
    switch reply.status {
    case 200: return Self.isCover(reply.data) ? reply.data : nil
    case 404: return nil
    default: throw .refused(status: reply.status)
    }
  }

  private static func isCover(_ image: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(image as CFData, nil),
      CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return false }
    return width < height && (width, height) != placeholder
  }

  /// A search term for `field`, quoted so that the whole `text` is searched in it.
  private static func phrase(_ field: String, _ text: String) -> String {
    "\(field):\"\(text.replacing("\"", with: ""))\""
  }

  /// A request URL: the `terms` are joined with "+", which Google reads as a space between them.
  private static func url(
    id: String? = nil, terms: [String] = [], parameters: [(name: String, value: String)]
  ) throws(LookupError) -> URL {
    var query = parameters.map { "\($0.name)=\(queryEscaped($0.value))" }
    if !terms.isEmpty { query.insert("q=" + terms.map(queryEscaped).joined(separator: "+"), at: 0) }
    let path = id.map { "/" + queryEscaped($0) } ?? ""
    guard let url = URL(string: "\(site)\(path)?" + query.joined(separator: "&")) else {
      throw .unreadable
    }
    return url
  }

  /// The user's key, which only ever goes into a request URL.
  private func apiKey() async throws(LookupError) -> String {
    let key: String?
    do {
      key = try await keys.password(for: LookupSource.googleBooksKeyAccount)
    } catch {
      throw .missingKey
    }
    guard let key, !key.isEmpty else { throw .missingKey }
    return key
  }

  /// The JSON at `url`, or nil for a 404 when `missingIsNil`.
  private func decoded<Record: Decodable>(
    at url: URL, missingIsNil: Bool = false
  ) async throws(LookupError) -> Record? {
    let reply = try await fetcher.get(url)
    switch reply.status {
    case 200:
      do {
        return try JSONDecoder().decode(Record.self, from: reply.data)
      } catch {
        throw .unreadable
      }
    case 400, 403: throw .missingKey
    case 404 where missingIsNil: return nil
    default: throw .refused(status: reply.status)
    }
  }

  private func found(_ volume: Volume, searched: String? = nil) -> FoundEdition {
    let info = volume.volumeInfo
    let identifiers = info.industryIdentifiers ?? []
    let isbns =
      identifiers.filter { $0.type == "ISBN_13" } + identifiers.filter { $0.type == "ISBN_10" }
    return FoundEdition(
      source: source,
      title: info.title,
      author: info.authors.flatMap { $0.isEmpty ? nil : $0.joined(separator: Self.separator) },
      year: info.publishedDate.flatMap(Self.year),
      isbn: foundISBN(in: isbns.map(\.identifier), searched: searched),
      language: info.language.flatMap { Self.unknownLanguages.contains($0) ? nil : $0 },
      publisher: info.publisher,
      cover: info.imageLinks?.largest.flatMap(Self.secure),
      thumbnail: info.imageLinks?.smallest.flatMap(Self.secure),
      link: (info.canonicalVolumeLink ?? info.infoLink).flatMap { URL(string: $0) })
  }

  /// The first four characters of `publishedDate` ("2017", "2017-03" or "2017-03-01"); never
  /// "0000", which Google sends for an unknown date.
  private static func year(of date: String) -> String? {
    let year = date.prefix(4)
    return year.count == 4 && year.allSatisfy { $0.isASCII && $0.isWholeNumber } && year != "0000"
      ? String(year) : nil
  }

  /// An image link over HTTPS, without the page-curl effect Google adds to covers.
  private static func secure(_ link: String) -> URL? {
    URL(
      string: link.replacing("http://", with: "https://", maxReplacements: 1)
        .replacing("&edge=curl", with: ""))
  }
}

private struct VolumeList: Decodable {
  let items: [Volume]?
}

private struct Volume: Decodable {
  let id: String
  let volumeInfo: VolumeInfo
}

private struct VolumeInfo: Decodable {
  struct Identifier: Decodable {
    let type: String
    let identifier: String
  }

  struct Images: Decodable {
    let smallThumbnail: String?
    let thumbnail: String?
    let small: String?
    let medium: String?
    let large: String?
    let extraLarge: String?

    var largest: String? { extraLarge ?? large ?? medium ?? small ?? thumbnail ?? smallThumbnail }
    var smallest: String? { thumbnail ?? smallThumbnail }
  }

  let title: String?
  let authors: [String]?
  let publisher: String?
  let publishedDate: String?
  let industryIdentifiers: [Identifier]?
  let language: String?
  let imageLinks: Images?
  let canonicalVolumeLink: String?
  let infoLink: String?
}
