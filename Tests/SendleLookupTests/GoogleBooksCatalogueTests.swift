import CoreGraphics
import Foundation
import ImageIO
import SendleDomain
import SendleLookup
import SendleTestSupport
import Testing
import UniformTypeIdentifiers
import os

@Suite(.timeLimit(.minutes(1)))
struct GoogleBooksCatalogueTests {
  static let isbn = "9788408172277"
  static let key = "test-key"
  static let volumes = "https://www.googleapis.com/books/v1/volumes"
  static let searchURL = "\(volumes)?q=isbn:\(isbn)&key=\(key)"
  static let volumeURL = "\(volumes)/Fx3dDwAAQBAJ?key=\(key)"
  static let listURL =
    "\(volumes)?q=intitle:Cien%20a%C3%B1os%20de%20soledad"
    + "+inauthor:Gabriel%20Garc%C3%ADa%20M%C3%A1rquez&printType=books&maxResults=10&key=\(key)"
    + "&langRestrict=es"
  static let coverURL =
    "https://books.google.com/books/content?id=X&printsec=frontcover&img=1&zoom=1&source=gbs_api"

  func catalogue(_ fetcher: some HTTPFetching) -> GoogleBooksCatalogue {
    GoogleBooksCatalogue(
      fetcher: fetcher,
      keys: MemorySecretStore([LookupSource.googleBooksKeyAccount: Self.key]))
  }

  func titleSearch(
    _ catalogue: GoogleBooksCatalogue, author: String? = "Gabriel García Márquez",
    language: String? = "es"
  ) async throws -> [FoundEdition] {
    try await catalogue.editions(title: "Cien años de soledad", author: author, language: language)
  }

  enum NoKey: CaseIterable {
    case absent
    case empty
    case unreadable

    var store: MemorySecretStore {
      switch self {
      case .absent: MemorySecretStore()
      case .empty: MemorySecretStore([LookupSource.googleBooksKeyAccount: ""])
      case .unreadable: MemorySecretStore(readFailure: .keychain(status: -25_308))
      }
    }
  }

  @Test(arguments: NoKey.allCases)
  func noKeyMakesNoRequest(_ state: NoKey) async {
    let fetcher = FixtureFetcher([:])
    let catalogue = GoogleBooksCatalogue(fetcher: fetcher, keys: state.store)
    await #expect(throws: LookupError.missingKey) { try await catalogue.edition(isbn: Self.isbn) }
    await #expect(throws: LookupError.missingKey) { try await titleSearch(catalogue) }
    #expect(fetcher.requests.isEmpty)
  }

  @Test func theKeyIsReadOnEveryCall() async throws {
    let keys = MemorySecretStore()
    let fetcher = FixtureFetcher([
      Self.searchURL: (200, "google/search-empty.json")
    ])
    let catalogue = GoogleBooksCatalogue(fetcher: fetcher, keys: keys)
    await #expect(throws: LookupError.missingKey) { try await catalogue.edition(isbn: Self.isbn) }
    await keys.setPassword(Self.key, for: LookupSource.googleBooksKeyAccount)
    #expect(try await catalogue.edition(isbn: Self.isbn) == nil)
    #expect(fetcher.requests == [Self.searchURL])
  }

  @Test func editionByISBNReadsTheVolume() async throws {
    let fetcher = FixtureFetcher([
      Self.searchURL: (200, "google/search-isbn.json"),
      Self.volumeURL: (200, "google/volume-los-ritos-del-agua.json"),
    ])
    let found = try #require(try await catalogue(fetcher).edition(isbn: Self.isbn))
    let content = "https://books.google.com/books/content?id=Fx3dDwAAQBAJ&printsec=frontcover&img=1"
    let page = "https://books.google.com/books/about/Los_ritos_del_agua.html?hl=&id=Fx3dDwAAQBAJ"
    #expect(
      found
        == FoundEdition(
          source: .googleBooks, title: "Los ritos del agua", author: "Eva García Sáenz de Urbina",
          year: "2017", isbn: Self.isbn, language: "es", publisher: "Planeta",
          cover: URL(string: "\(content)&zoom=6&source=gbs_api"),
          thumbnail: URL(string: "\(content)&zoom=1&source=gbs_api"),
          link: URL(string: page)))
    #expect(fetcher.requests == [Self.searchURL, Self.volumeURL])
  }

  @Test func unknownISBNIsNil() async throws {
    let fetcher = FixtureFetcher([Self.searchURL: (200, "google/search-empty.json")])
    #expect(try await catalogue(fetcher).edition(isbn: Self.isbn) == nil)
    #expect(fetcher.requests == [Self.searchURL])
  }

  @Test func aVolumeThatIsGoneIsNil() async throws {
    let fetcher = FixtureFetcher([
      Self.searchURL: (200, "google/search-isbn.json"),
      Self.volumeURL: (404, "google/not-found-404.json"),
    ])
    #expect(try await catalogue(fetcher).edition(isbn: Self.isbn) == nil)
    #expect(fetcher.requests == [Self.searchURL, Self.volumeURL])
  }

  @Test func aSearchThatIsNotFoundIsRefused() async {
    let fetcher = FixtureFetcher([Self.searchURL: (404, "google/not-found-404.json")])
    await #expect(throws: LookupError.refused(status: 404)) {
      try await catalogue(fetcher).edition(isbn: Self.isbn)
    }
  }

  @Test(arguments: [(400, "google/bad-key-400.json"), (403, "google/forbidden-403.json")])
  func rejectedKeyNeedsAKey(status: Int, file: String) async {
    let fetcher = FixtureFetcher([Self.searchURL: (status, file)])
    await #expect(throws: LookupError.missingKey) {
      try await catalogue(fetcher).edition(isbn: Self.isbn)
    }
  }

  @Test func rejectedKeyOnAListNeedsAKey() async {
    let fetcher = FixtureFetcher([Self.listURL: (400, "google/bad-key-400.json")])
    await #expect(throws: LookupError.missingKey) { try await titleSearch(catalogue(fetcher)) }
  }

  @Test func rejectedKeyOnTheVolumeNeedsAKey() async {
    let fetcher = FixtureFetcher([
      Self.searchURL: (200, "google/search-isbn.json"),
      Self.volumeURL: (403, "google/forbidden-403.json"),
    ])
    await #expect(throws: LookupError.missingKey) {
      try await catalogue(fetcher).edition(isbn: Self.isbn)
    }
  }

  @Test func quotaIsRefused() async {
    let fetcher = FixtureFetcher([Self.searchURL: (429, "google/quota-429.json")])
    await #expect(throws: LookupError.refused(status: 429)) {
      try await catalogue(fetcher).edition(isbn: Self.isbn)
    }
  }

  @Test func htmlReplyIsUnreadable() async {
    let fetcher = FixtureFetcher([Self.searchURL: (200, "google/html-200.html")])
    await #expect(throws: LookupError.unreadable) {
      try await catalogue(fetcher).edition(isbn: Self.isbn)
    }
  }

  @Test func listCarriesLanguageRestriction() async throws {
    let fetcher = FixtureFetcher([Self.listURL: (200, "google/list-cien-anos.json")])
    let found = try await titleSearch(catalogue(fetcher))
    #expect(found.count == 3)
    #expect(found.allSatisfy { $0.source == .googleBooks })
    #expect(fetcher.requests == [Self.listURL])
    #expect(try #require(fetcher.requests.first).contains("&langRestrict=es"))
  }

  @Test func listItemsAreMappedWithoutFurtherRequests() async throws {
    let fetcher = FixtureFetcher([Self.listURL: (200, "google/list-cien-anos.json")])
    let found = try await titleSearch(catalogue(fetcher))
    let first = "https://books.google.com/books/content?id=kQ2xDwAAQBAJ&printsec=frontcover&img=1"
    let third = "https://books.google.com/books/content?id=t0hZDwAAQBAJ&printsec=frontcover&img=1"
    #expect(
      found == [
        FoundEdition(
          source: .googleBooks, title: "Cien años de soledad", author: "Gabriel García Márquez",
          year: "2009", isbn: "9780307474728", language: "es", publisher: "Debolsillo",
          cover: URL(string: "\(first)&zoom=1&source=gbs_api"),
          thumbnail: URL(string: "\(first)&zoom=1&source=gbs_api"),
          link: URL(
            string: "https://books.google.com/books/about/Cien_a%C3%B1os_de_soledad.html"
              + "?hl=&id=kQ2xDwAAQBAJ")),
        FoundEdition(
          source: .googleBooks, title: "Cien años de soledad",
          author: "Gabriel García Márquez & Gregory Rabassa", year: "1988",
          isbn: "9788439711087", language: "es", publisher: "Mondadori",
          link: URL(
            string: "http://books.google.com/books?id=m9RtEAAAQBAJ&dq=intitle:Cien+inauthor:Gabriel"
              + "&hl=&source=gbs_api")),
        FoundEdition(
          source: .googleBooks, title: "Cien años de soledad (edición conmemorativa)",
          year: "1967",
          cover: URL(string: "\(third)&zoom=5&source=gbs_api"),
          thumbnail: URL(string: "\(third)&zoom=5&source=gbs_api"),
          link: URL(
            string: "http://books.google.com/books?id=t0hZDwAAQBAJ&dq=intitle:Cien+inauthor:Gabriel"
              + "&hl=&source=gbs_api")),
      ])
  }

  @Test func listLeavesOutWhatIsMissing() async throws {
    let url =
      "\(Self.volumes)?q=intitle:Cien%20a%C3%B1os%20de%20soledad&printType=books&maxResults=10"
      + "&key=\(Self.key)"
    let fetcher = FixtureFetcher([url: (200, "google/search-empty.json")])
    #expect(try await titleSearch(catalogue(fetcher), author: nil, language: nil) == [])
    #expect(fetcher.requests == [url])
  }

  @Test func listEncodesPlusAndAmpersand() async throws {
    let url =
      "\(Self.volumes)?q=intitle:C%2B%2B%20%26%20Go&printType=books&maxResults=10&key=\(Self.key)"
    let fetcher = FixtureFetcher([url: (200, "google/search-empty.json")])
    _ = try await catalogue(fetcher).editions(title: "C++ & Go", author: nil, language: nil)
    #expect(fetcher.requests == [url])
  }

  @Test func listFailureIsRefused() async {
    let fetcher = FixtureFetcher([Self.listURL: (429, "google/quota-429.json")])
    await #expect(throws: LookupError.refused(status: 429)) {
      try await titleSearch(catalogue(fetcher))
    }
  }

  static let dates: [(date: String, year: String?)] = [
    ("2017", "2017"), ("2017-03", "2017"), ("2017-03-01", "2017"), ("201", nil), ("", nil),
    ("n.d.", nil), ("c. 1999", nil), ("١٩٨٨", nil),
  ]

  @Test(arguments: dates)
  func yearIsTheFirstFourCharactersWhenTheyAreDigits(date: String, year: String?) async throws {
    let json = #"{"items":[{"id":"a","volumeInfo":{"publishedDate":"\#(date)"}}]}"#
    let fetcher = DataFetcher([Self.listURL: (200, Data(json.utf8))])
    let found = try await titleSearch(catalogue(fetcher))
    #expect(found.map(\.year) == [year])
  }

  @Test(arguments: [
    (128, 170, false), (300, 48, false), (400, 600, true), (129, 170, true), (128, 171, true),
    (170, 128, false), (200, 200, false),
  ])
  func placeholderImagesAreDropped(width: Int, height: Int, isCover: Bool) async throws {
    let picture = try Pictures.png(width: width, height: height)
    let fetcher = DataFetcher([Self.coverURL: (200, picture)])
    let data = try await catalogue(fetcher).image(at: #require(URL(string: Self.coverURL)))
    #expect(data == (isCover ? picture : nil))
    #expect(fetcher.requests == [Self.coverURL])
  }

  @Test func anImageThatWillNotDecodeIsDropped() async throws {
    let fetcher = DataFetcher([Self.coverURL: (200, Data("<html>Sign in</html>".utf8))])
    #expect(try await catalogue(fetcher).image(at: #require(URL(string: Self.coverURL))) == nil)
  }

  @Test func aMissingImageIsNil() async throws {
    let fetcher = DataFetcher([Self.coverURL: (404, Data())])
    #expect(try await catalogue(fetcher).image(at: #require(URL(string: Self.coverURL))) == nil)
  }

  @Test func aRefusedImageThrows() async throws {
    let fetcher = DataFetcher([Self.coverURL: (503, Data())])
    let url = try #require(URL(string: Self.coverURL))
    await #expect(throws: LookupError.refused(status: 503)) {
      try await catalogue(fetcher).image(at: url)
    }
  }
}

/// Answers each URL it was given with the status and bytes it was given for it, and records what
/// was asked. An URL it wasn't given fails the test.
private struct DataFetcher: HTTPFetching {
  private let replies: [String: (status: Int, data: Data)]
  private let asked = OSAllocatedUnfairLock<[String]>(initialState: [])

  init(_ replies: [String: (Int, Data)]) {
    self.replies = replies.mapValues { (status: $0.0, data: $0.1) }
  }

  var requests: [String] { asked.withLock { $0 } }

  func get(_ url: URL) async throws(LookupError) -> HTTPReply {
    asked.withLock { $0.append(url.absoluteString) }
    guard let reply = replies[url.absoluteString] else {
      Issue.record("Unexpected request: \(url.absoluteString)")
      throw .unreadable
    }
    return HTTPReply(status: reply.status, data: reply.data)
  }
}

private enum Pictures {
  struct Failure: Error {}

  /// A solid PNG of the given size.
  static func png(width: Int, height: Int) throws -> Data {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Failure() }
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { throw Failure() }
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
    else { throw Failure() }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw Failure() }
    return data as Data
  }
}
