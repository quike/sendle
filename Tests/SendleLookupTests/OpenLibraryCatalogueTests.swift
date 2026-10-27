import Foundation
import SendleDomain
import SendleLookup
import Testing

@Suite(.timeLimit(.minutes(1)))
struct OpenLibraryCatalogueTests {
  static let spanishISBN = "9786070714863"
  static let spanishEditionURL = "https://openlibrary.org/isbn/9786070714863.json"
  static let tenOnlyISBN = "9788439711087"
  static let tenOnlyEditionURL = "https://openlibrary.org/isbn/9788439711087.json"
  static let twoAuthorsEditionURL = "https://openlibrary.org/isbn/9780060114183.json"
  static let unknownISBN = "9788408172277"
  static let unknownEditionURL = "https://openlibrary.org/isbn/9788408172277.json"
  static let marquezURL = "https://openlibrary.org/authors/OL27363A.json"
  static let rabassaURL = "https://openlibrary.org/authors/OL2631013A.json"
  static let workURL = "https://openlibrary.org/works/OL274505W.json"
  static let searchURL =
    "https://openlibrary.org/search.json?title=Cien%20a%C3%B1os%20de%20soledad"
    + "&author=Gabriel%20Garc%C3%ADa%20M%C3%A1rquez&limit=5&fields=key,title,author_name&lang=es"
  static let firstEditionsURL = "https://openlibrary.org/works/OL274505W/editions.json?limit=50"
  static let secondEditionsURL = "https://openlibrary.org/works/OL25917022W/editions.json?limit=50"
  static let originalCoverURL = "https://covers.openlibrary.org/b/id/12808734.jpg"
  static let largeCoverURL = "https://covers.openlibrary.org/b/id/12808734-L.jpg?default=false"

  static let marquez = "Gabriel García Márquez"

  func catalogue(_ fetcher: FixtureFetcher) -> OpenLibraryCatalogue {
    OpenLibraryCatalogue(fetcher: fetcher)
  }

  func titleSearch(
    _ catalogue: OpenLibraryCatalogue, author: String? = Self.marquez, language: String? = "es"
  ) async throws -> [FoundEdition] {
    try await catalogue.editions(title: "Cien años de soledad", author: author, language: language)
  }

  @Test func editionByISBN() async throws {
    let fetcher = FixtureFetcher([
      Self.spanishEditionURL: (200, "openlibrary/isbn-spanish.json"),
      Self.marquezURL: (200, "openlibrary/author-OL27363A.json"),
    ])
    let found = try #require(try await catalogue(fetcher).edition(isbn: Self.spanishISBN))
    #expect(
      found
        == FoundEdition(
          source: .openLibrary, title: "Cien años de soledad", author: Self.marquez,
          year: "2012", isbn: Self.spanishISBN, language: "es", publisher: "Diana",
          cover: URL(string: Self.originalCoverURL),
          thumbnail: URL(
            string: "https://covers.openlibrary.org/b/id/12808734-M.jpg?default=false"),
          link: URL(string: "https://openlibrary.org/books/OL38570141M")))
    #expect(fetcher.requests == [Self.spanishEditionURL, Self.marquezURL])
  }

  @Test func theISBNSearchedIsTheOneFoundWhenTheEditionListsSeveral() async throws {
    let fetcher = FixtureFetcher([
      Self.spanishEditionURL: (200, "openlibrary/isbn-two-isbns.json"),
      Self.unknownEditionURL: (200, "openlibrary/isbn-two-isbns.json"),
      Self.marquezURL: (200, "openlibrary/author-OL27363A.json"),
    ])
    let searched = try await catalogue(fetcher).edition(isbn: Self.spanishISBN)
    #expect(searched?.isbn == Self.spanishISBN)
    let unlisted = try await catalogue(fetcher).edition(isbn: Self.unknownISBN)
    #expect(unlisted?.isbn == "9786070728792")
  }

  @Test func isbnTenAndWorkAuthorsAndMissingCover() async throws {
    let fetcher = FixtureFetcher([
      Self.tenOnlyEditionURL: (200, "openlibrary/isbn-ten-only.json"),
      Self.workURL: (200, "openlibrary/work-OL274505W.json"),
      Self.marquezURL: (200, "openlibrary/author-OL27363A.json"),
    ])
    let found = try #require(try await catalogue(fetcher).edition(isbn: Self.tenOnlyISBN))
    #expect(found.isbn == Self.tenOnlyISBN)
    #expect(found.author == Self.marquez)
    #expect(found.year == "1988")
    #expect(found.publisher == "Mondadori")
    #expect(found.cover?.absoluteString == "https://covers.openlibrary.org/b/id/14359127.jpg")
    #expect(fetcher.requests == [Self.tenOnlyEditionURL, Self.workURL, Self.marquezURL])
  }

  @Test func severalAuthorsAreJoined() async throws {
    let fetcher = FixtureFetcher([
      Self.twoAuthorsEditionURL: (200, "openlibrary/isbn-two-authors.json"),
      Self.marquezURL: (200, "openlibrary/author-OL27363A.json"),
      Self.rabassaURL: (200, "openlibrary/author-OL2631013A.json"),
    ])
    let found = try #require(try await catalogue(fetcher).edition(isbn: "9780060114183"))
    #expect(found.author == "\(Self.marquez) & Gregory Rabassa")
    #expect(found.year == "1970")
    #expect(found.language == "en")
    #expect(fetcher.requests == [Self.twoAuthorsEditionURL, Self.marquezURL, Self.rabassaURL])
  }

  @Test func anAuthorWhoseRecordIsGoneIsLeftOut() async throws {
    let fetcher = FixtureFetcher([
      Self.spanishEditionURL: (200, "openlibrary/isbn-spanish.json"),
      Self.marquezURL: (404, "openlibrary/not-found-404.html"),
    ])
    let found = try #require(try await catalogue(fetcher).edition(isbn: Self.spanishISBN))
    #expect(found.author == nil)
    #expect(found.title == "Cien años de soledad")
  }

  @Test func unknownISBNIsNil() async throws {
    let fetcher = FixtureFetcher([
      Self.unknownEditionURL: (404, "openlibrary/not-found-404.html")
    ])
    #expect(try await catalogue(fetcher).edition(isbn: Self.unknownISBN) == nil)
  }

  @Test func htmlReplyIsUnreadable() async {
    let fetcher = FixtureFetcher([Self.spanishEditionURL: (200, "openlibrary/html-200.html")])
    await #expect(throws: LookupError.unreadable) {
      try await catalogue(fetcher).edition(isbn: Self.spanishISBN)
    }
  }

  @Test func serverErrorIsRefused() async {
    let fetcher = FixtureFetcher([
      Self.spanishEditionURL: (503, "openlibrary/unavailable-503.html")
    ])
    await #expect(throws: LookupError.refused(status: 503)) {
      try await catalogue(fetcher).edition(isbn: Self.spanishISBN)
    }
  }

  @Test func editionsByTitleUseTheWorksAuthors() async throws {
    let fetcher = FixtureFetcher([
      Self.searchURL: (200, "openlibrary/search-cien-anos.json"),
      Self.firstEditionsURL: (200, "openlibrary/editions-OL274505W.json"),
      Self.secondEditionsURL: (200, "openlibrary/editions-OL25917022W.json"),
    ])
    let found = try await titleSearch(catalogue(fetcher))
    #expect(found.count == 51)
    #expect(found.allSatisfy { $0.source == .openLibrary && $0.author == Self.marquez })
    #expect(fetcher.requests == [Self.searchURL, Self.firstEditionsURL, Self.secondEditionsURL])
  }

  @Test func editionsByTitleCarryNormalisedISBNsAndFourDigitYears() async throws {
    let fetcher = FixtureFetcher([
      Self.searchURL: (200, "openlibrary/search-cien-anos.json"),
      Self.firstEditionsURL: (200, "openlibrary/editions-OL274505W.json"),
      Self.secondEditionsURL: (200, "openlibrary/editions-OL25917022W.json"),
    ])
    let found = try await titleSearch(catalogue(fetcher))
    let hyphenated = try #require(found.first { $0.link?.lastPathComponent == "OL60001193M" })
    #expect(hyphenated.isbn == "9788804809845")
    let letterO = try #require(found.first { $0.link?.lastPathComponent == "OL62012175M" })
    #expect(letterO.year == "1995")
    let tenOnly = try #require(found.first { $0.link?.lastPathComponent == "OL48571928M" })
    #expect(tenOnly.isbn == Self.tenOnlyISBN)
    #expect(found.contains { $0.isbn == nil })
    let digits = Set("0123456789")
    #expect(found.compactMap(\.isbn).allSatisfy { $0.count == 13 && Set($0).isSubset(of: digits) })
    #expect(found.compactMap(\.year).allSatisfy { $0.count == 4 && Set($0).isSubset(of: digits) })
  }

  @Test func searchURLCarriesLanguage() async throws {
    let fetcher = FixtureFetcher([Self.searchURL: (200, "openlibrary/search-empty.json")])
    _ = try await titleSearch(catalogue(fetcher))
    #expect(fetcher.requests == [Self.searchURL])
  }

  @Test func searchURLLeavesOutWhatIsMissing() async throws {
    let url =
      "https://openlibrary.org/search.json?title=Cien%20a%C3%B1os%20de%20soledad"
      + "&limit=5&fields=key,title,author_name"
    let fetcher = FixtureFetcher([url: (200, "openlibrary/search-empty.json")])
    #expect(try await titleSearch(catalogue(fetcher), author: nil, language: nil) == [])
    #expect(fetcher.requests == [url])
  }

  @Test func searchURLEncodesPlusAndAmpersand() async throws {
    let url =
      "https://openlibrary.org/search.json?title=C%2B%2B%20%26%20Go&limit=5"
      + "&fields=key,title,author_name"
    let fetcher = FixtureFetcher([url: (200, "openlibrary/search-empty.json")])
    _ = try await catalogue(fetcher).editions(title: "C++ & Go", author: nil, language: nil)
    #expect(fetcher.requests == [url])
  }

  @Test func searchFailureIsRefused() async {
    let fetcher = FixtureFetcher([Self.searchURL: (503, "openlibrary/unavailable-503.html")])
    await #expect(throws: LookupError.refused(status: 503)) {
      try await titleSearch(catalogue(fetcher))
    }
  }

  @Test func originalCoverWinsWhenItIsAnImage() async throws {
    let fetcher = FixtureFetcher([Self.originalCoverURL: (200, "openlibrary/cover.jpg")])
    let data = try await catalogue(fetcher).image(at: #require(URL(string: Self.originalCoverURL)))
    #expect(data == (try FixtureFetcher.fixture("openlibrary/cover.jpg")))
    #expect(fetcher.requests == [Self.originalCoverURL])
  }

  @Test func originalCoverFallsBackToLarge() async throws {
    let fetcher = FixtureFetcher([
      Self.originalCoverURL: (404, "openlibrary/not-found-404.html"),
      Self.largeCoverURL: (200, "openlibrary/cover.jpg"),
    ])
    let data = try await catalogue(fetcher).image(at: #require(URL(string: Self.originalCoverURL)))
    #expect(data == (try FixtureFetcher.fixture("openlibrary/cover.jpg")))
    #expect(fetcher.requests == [Self.originalCoverURL, Self.largeCoverURL])
  }

  @Test func aPlaceholderIsNotAnImage() async throws {
    let fetcher = FixtureFetcher([
      Self.originalCoverURL: (200, "openlibrary/placeholder.gif"),
      Self.largeCoverURL: (404, "openlibrary/not-found-404.html"),
    ])
    #expect(
      try await catalogue(fetcher).image(at: #require(URL(string: Self.originalCoverURL))) == nil)
    #expect(fetcher.requests == [Self.originalCoverURL, Self.largeCoverURL])
  }

  @Test func onlyAnOriginalCoverFallsBack() async throws {
    let thumbnail = "https://covers.openlibrary.org/b/id/12808734-M.jpg?default=false"
    let fetcher = FixtureFetcher([thumbnail: (404, "openlibrary/not-found-404.html")])
    #expect(try await catalogue(fetcher).image(at: #require(URL(string: thumbnail))) == nil)
    #expect(fetcher.requests == [thumbnail])
  }

  @Test func aRefusedImageThrows() async throws {
    let fetcher = FixtureFetcher([
      Self.originalCoverURL: (503, "openlibrary/unavailable-503.html")
    ])
    let url = try #require(URL(string: Self.originalCoverURL))
    await #expect(throws: LookupError.refused(status: 503)) {
      try await catalogue(fetcher).image(at: url)
    }
  }

  @Test(arguments: [(999, false), (1000, true)])
  func anImageIsAThousandBytesOrMore(size: Int, isImage: Bool) async throws {
    let fetcher = SizedFetcher(size: size)
    let url = try #require(URL(string: "https://covers.openlibrary.org/b/id/1-M.jpg"))
    let data = try await OpenLibraryCatalogue(fetcher: fetcher).image(at: url)
    #expect((data != nil) == isImage)
  }

  @Test func firstYearOfFreeText() {
    #expect(firstYear(in: "October 1, 1988") == "1988")
    #expect(firstYear(in: "1984") == "1984")
    #expect(firstYear(in: "O5/06/1995") == "1995")
    #expect(firstYear(in: "1970-01-01") == "1970")
    #expect(firstYear(in: "c. 12345 1999") == "1999")
    #expect(firstYear(in: "c. 12345") == nil)
    #expect(firstYear(in: "١٩٨٨") == nil)
    #expect(firstYear(in: "") == nil)
  }

  @Test func marcCodes() {
    #expect(MARCLanguages.bcp47("spa") == "es")
    #expect(MARCLanguages.bcp47("xxx") == nil)
  }

  @Test(arguments: [
    ("afr", "af"), ("ara", "ar"), ("baq", "eu"), ("bre", "br"), ("cat", "ca"), ("chi", "zh"),
    ("cor", "kw"), ("cos", "co"), ("cze", "cs"), ("dan", "da"), ("dut", "nl"), ("eng", "en"),
    ("fin", "fi"), ("fre", "fr"), ("frr", "frr"), ("fry", "fy"), ("ger", "de"), ("gla", "gd"),
    ("gle", "ga"), ("glg", "gl"), ("glv", "gv"), ("gre", "el"), ("gsw", "gsw"), ("guj", "gu"),
    ("heb", "he"), ("hin", "hi"), ("hun", "hu"), ("ice", "is"), ("ita", "it"), ("jpn", "ja"),
    ("kor", "ko"), ("lat", "la"), ("ltz", "lb"), ("mal", "ml"), ("mar", "mr"), ("nno", "nn"),
    ("nob", "nb"), ("nor", "nb"), ("oci", "oc"), ("pol", "pl"), ("por", "pt"), ("roh", "rm"),
    ("rum", "ro"), ("rus", "ru"), ("sco", "sco"), ("spa", "es"), ("swe", "sv"), ("tam", "ta"),
    ("tur", "tr"), ("ukr", "uk"), ("wel", "cy"),
  ])
  func marcTable(code: String, tag: String) {
    #expect(MARCLanguages.bcp47(code) == tag)
  }
}

/// Answers every request with a 200 and `size` bytes.
private struct SizedFetcher: HTTPFetching {
  let size: Int

  func get(_ url: URL) async throws(LookupError) -> HTTPReply {
    HTTPReply(status: 200, data: Data(count: size))
  }
}
