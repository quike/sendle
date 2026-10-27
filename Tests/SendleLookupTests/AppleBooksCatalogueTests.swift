import Foundation
import SendleDomain
import SendleLookup
import Testing

@Suite(.timeLimit(.minutes(1)))
struct AppleBooksCatalogueTests {
  static let isbn = "9788408170877"
  static let unrelatedISBN = "9788408172277"
  static let emptyISBN = "9789999999991"
  static let site = "https://itunes.apple.com"
  static let lookupURL = "\(site)/lookup?isbn=\(isbn)&country=es"
  static let searchURL =
    "\(site)/search?term=Los%20ritos%20del%20agua%20Eva%20Garc%C3%ADa%20S%C3%A1enz"
    + "&media=ebook&entity=ebook&limit=10&country=es"
  static let ritosArtwork =
    "https://is1-ssl.mzstatic.com/image/thumb/Publication122/v4/9b/b2/f1/"
    + "9bb2f10c-dc5a-b0a3-77ef-db0d21cfd556/9788408170877.jpg"
  static let coverURL = "\(ritosArtwork)/3000x3000bb.jpg"

  static let ritos = FoundEdition(
    source: .appleBooks, title: "Los ritos del agua", author: "Eva García Saénz de Urturi",
    cover: URL(string: coverURL),
    thumbnail: URL(string: "\(ritosArtwork)/200x200bb.jpg"),
    link: URL(string: "https://books.apple.com/es/book/los-ritos-del-agua/id1211896224?uo=4"))

  func catalogue(_ fetcher: some HTTPFetching, storefront: String = "es") -> AppleBooksCatalogue {
    AppleBooksCatalogue(fetcher: fetcher, storefront: storefront)
  }

  func titleSearch(
    _ catalogue: AppleBooksCatalogue, title: String = "Los ritos del agua",
    author: String? = "Eva García Sáenz", language: String? = "es"
  ) async throws -> [FoundEdition] {
    try await catalogue.editions(title: title, author: author, language: language)
  }

  @Test func editionHasNoDateEvenWithReleaseDate() async throws {
    let fetcher = FixtureFetcher([Self.lookupURL: (200, "apple/lookup-los-ritos-del-agua.json")])
    let found = try #require(try await catalogue(fetcher).edition(isbn: Self.isbn))
    #expect(found == Self.ritos)
    #expect(found.year == nil && found.isbn == nil && found.language == nil)
    #expect(found.publisher == nil)
    #expect(found.cover?.absoluteString.contains("3000x3000bb") == true)
    #expect(fetcher.requests == [Self.lookupURL])
  }

  @Test func anotherBookIsReturnedAsItIs() async throws {
    let url = "\(Self.site)/lookup?isbn=\(Self.unrelatedISBN)&country=es"
    let fetcher = FixtureFetcher([url: (200, "apple/lookup-unrelated-book.json")])
    let found = try #require(try await catalogue(fetcher).edition(isbn: Self.unrelatedISBN))
    #expect(found.title == "Los héroes del tiempo")
    #expect(found.author == "Francesc Marí")
  }

  @Test(arguments: ["es", "us"])
  func storefrontGoesInTheURL(_ storefront: String) async throws {
    let lookup = "\(Self.site)/lookup?isbn=\(Self.isbn)&country=\(storefront)"
    let search = Self.searchURL.replacing("&country=es", with: "&country=\(storefront)")
    let fetcher = FixtureFetcher([
      lookup: (200, "apple/lookup-empty.json"), search: (200, "apple/search-empty.json"),
    ])
    let catalogue = catalogue(fetcher, storefront: storefront)
    _ = try await catalogue.edition(isbn: Self.isbn)
    _ = try await titleSearch(catalogue)
    #expect(fetcher.requests == [lookup, search])
    #expect(fetcher.requests.allSatisfy { $0.hasSuffix("&country=\(storefront)") })
  }

  @Test func emptyAnswerIsNil() async throws {
    let url = "\(Self.site)/lookup?isbn=\(Self.emptyISBN)&country=es"
    let fetcher = FixtureFetcher([url: (200, "apple/lookup-empty.json")])
    #expect(try await catalogue(fetcher).edition(isbn: Self.emptyISBN) == nil)
    #expect(fetcher.requests == [url])
  }

  @Test func theFirstEbookWinsAndTheRestAreLeftOut() async throws {
    let fetcher = FixtureFetcher([Self.lookupURL: (200, "apple/mixed-kinds.json")])
    let found = try await catalogue(fetcher).edition(isbn: Self.isbn)
    #expect(found == FoundEdition(source: .appleBooks, title: "Un libro sin portada"))
  }

  @Test func searchListsEbooks() async throws {
    let fetcher = FixtureFetcher([Self.searchURL: (200, "apple/search-los-ritos-del-agua.json")])
    let found = try await titleSearch(catalogue(fetcher))
    #expect(
      found.map(\.title) == [
        "Los ritos del agua", "Aquitania", "El silencio de la ciudad blanca",
        "Premio Planeta 2020: ganador y finalista (pack)", "Aquitania",
      ])
    #expect(found.first == Self.ritos)
    #expect(found.last?.author == "Eva García Saénz de Urturi")
    #expect(found.allSatisfy { $0.source == .appleBooks })
    #expect(
      found.allSatisfy { $0.year == nil && $0.isbn == nil && $0.language == nil }
        && found.allSatisfy { $0.publisher == nil })
    #expect(fetcher.requests == [Self.searchURL])
  }

  @Test func searchLeavesOutWhatIsNotAnEbook() async throws {
    let fetcher = FixtureFetcher([Self.searchURL: (200, "apple/mixed-kinds.json")])
    let found = try await titleSearch(catalogue(fetcher))
    #expect(found.map(\.title) == ["Un libro sin portada", "Los ritos del agua"])
  }

  @Test(arguments: ["es", "fr", nil] as [String?])
  func searchIgnoresTheLanguage(_ language: String?) async throws {
    let fetcher = FixtureFetcher([Self.searchURL: (200, "apple/search-empty.json")])
    #expect(try await titleSearch(catalogue(fetcher), language: language) == [])
    #expect(fetcher.requests == [Self.searchURL])
  }

  @Test func searchWithoutAnAuthorAsksForTheTitleOnly() async throws {
    let url = "\(Self.site)/search?term=Los%20ritos%20del%20agua&media=ebook&entity=ebook&limit=10"
    let fetcher = FixtureFetcher([url + "&country=es": (200, "apple/search-empty.json")])
    #expect(try await titleSearch(catalogue(fetcher), author: nil) == [])
    #expect(fetcher.requests == [url + "&country=es"])
  }

  @Test func searchEncodesWhatCouldBeSyntax() async throws {
    let url =
      "\(Self.site)/search?term=C%2B%2B%20%26%20Go%20%3D%20a%2Fb%3F&media=ebook&entity=ebook"
      + "&limit=10&country=es"
    let fetcher = FixtureFetcher([url: (200, "apple/search-empty.json")])
    _ = try await titleSearch(catalogue(fetcher), title: "C++ & Go = a/b?", author: nil)
    #expect(fetcher.requests == [url])
  }

  @Test func htmlReplyIsUnreadable() async {
    let fetcher = FixtureFetcher([
      Self.lookupURL: (200, "apple/html-200.html"), Self.searchURL: (200, "apple/html-200.html"),
    ])
    let catalogue = catalogue(fetcher)
    await #expect(throws: LookupError.unreadable) { try await catalogue.edition(isbn: Self.isbn) }
    await #expect(throws: LookupError.unreadable) { try await titleSearch(catalogue) }
  }

  @Test func jsonWithoutResultsIsUnreadable() async {
    let error = Data(#"{"errorMessage":"Invalid value(s) for key(s): [country]"}"#.utf8)
    let fetcher = DataFetcher([Self.lookupURL: (200, error)])
    await #expect(throws: LookupError.unreadable) {
      try await catalogue(fetcher).edition(isbn: Self.isbn)
    }
  }

  @Test(arguments: [400, 403, 404, 429, 503])
  func aStatusThatIsNotOKIsRefused(_ status: Int) async {
    let fetcher = DataFetcher([
      Self.lookupURL: (status, Data()), Self.searchURL: (status, Data()),
    ])
    let catalogue = catalogue(fetcher)
    await #expect(throws: LookupError.refused(status: status)) {
      try await catalogue.edition(isbn: Self.isbn)
    }
    await #expect(throws: LookupError.refused(status: status)) { try await titleSearch(catalogue) }
  }

  @Test func imageIsTheBytesOfAnOKReply() async throws {
    let picture = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
    let fetcher = DataFetcher([Self.coverURL: (200, picture)])
    let url = try #require(URL(string: Self.coverURL))
    #expect(try await catalogue(fetcher).image(at: url) == picture)
    #expect(fetcher.requests == [Self.coverURL])
  }

  @Test(arguments: [403, 404, 503])
  func imageIsNilForAnythingElse(_ status: Int) async throws {
    let fetcher = DataFetcher([Self.coverURL: (status, Data("not a picture".utf8))])
    let url = try #require(URL(string: Self.coverURL))
    #expect(try await catalogue(fetcher).image(at: url) == nil)
  }
}
