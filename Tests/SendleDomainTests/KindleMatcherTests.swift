import SendleDomain
import SendleTestSupport
import Testing

struct KindleMatcherTests {
  let moby = Book.fixture(id: "moby")

  func match(
    _ book: Book = .fixture(id: "moby"), _ listing: [KindleBook],
    editions: [BookID: Edition] = [:], editionASINs: [BookID: Set<String>] = [:],
    emailed: Set<BookID> = [], same: Set<ContentPair> = []
  ) -> KindleMatch? {
    KindleMatcher.matches(
      books: [book], editions: editions, editionASINs: editionASINs, emailed: emailed,
      sameContent: same, listing: listing
    ).byBook[book.id]
  }

  @Test func anEditionASINIsSure() {
    let found = match(
      moby, [.fixture(title: "Other", source: .sendle, asin: "SNEDITION1")],
      editionASINs: [moby.id: ["SNEDITION1", "SNEDITION2"]])
    #expect(found?.confidence == .sure)
    #expect(found?.reason == .editionKey)
  }

  @Test func anEditionASINOfAnotherTitleAndAuthorIsNoMatch() {
    let found = match(
      moby,
      [.fixture(title: "Dracula", authors: ["Bram Stoker"], source: .sendle, asin: "SNEDITION1")],
      editionASINs: [moby.id: ["SNEDITION1"]])
    #expect(found == nil)
  }

  @Test func equalISBNsAreSureWhateverTheirForm() {
    let found = match(
      moby, [.fixture(title: "Other", isbn: "978-0-306-40615-7")],
      editions: [moby.id: Edition(isbn: "urn:isbn:0306406152")])
    #expect(found?.reason == .isbn)
    #expect(found?.confidence == .sure)
  }

  @Test func thePDFsSameContentIsSure() {
    let pdf = Book.fixture(id: "orwell", title: "1984", author: "George Orwell", format: .pdf)
    let copy = KindleBook.fixture(path: "scan.pdf", title: "scan", authors: [])
    let found = match(pdf, [copy], same: [ContentPair(book: pdf.id, kindleBook: copy.id)])
    #expect(found?.reason == .sameContent)
    #expect(found?.confidence == .sure)
  }

  @Test func sendlesOlderCopiesAreSure() {
    let older = KindleBook.fixture(
      title: "Moby Dick", source: .sendle, asin: "SNFNYTPPHY", asinFollowsFileName: true)
    #expect(match(moby, [older])?.reason == .sendleName)
    let otherEdition = KindleBook.fixture(source: .sendle, asin: "SNOTHERED1")
    #expect(
      match(moby, [otherEdition], editionASINs: [moby.id: ["SNEDITION1"]])?.confidence == .maybe)
  }

  @Test func titleAndAuthorAloneAreOnlyAMaybe() {
    let found = match(
      moby,
      [
        .fixture(
          path: "Melville, Herman/Moby Dick.mobi", title: "Moby Dick",
          authors: ["Melville, Herman"])
      ])
    #expect(found?.confidence == .maybe)
    #expect(found?.reason == .titleAndAuthor)
  }

  @Test func aBookWithoutAnAuthorMatchesOnTitleOnlyAsAMaybe() {
    let orwell = Book.fixture(id: "orwell", title: "1984", author: "George Orwell", format: .pdf)
    let found = match(orwell, [.fixture(path: "1984.pdf", title: "1984", authors: [])])
    #expect(found?.reason == .titleOnly)
    #expect(found?.confidence == .maybe)
  }

  @Test func anEmailedBookNamedByItsTitleIsSureOnlyWithHistory() {
    let bleak = Book.fixture(id: "bleak", title: "Bleak House", author: "Charles Dickens")
    let download = KindleBook.fixture(
      path: "Downloads/Items01/Bleak House_0123456789ABCDEF0123456789ABCDEF.kfx",
      title: "Bleak House", authors: [], source: .email)
    #expect(match(bleak, [download], emailed: [bleak.id])?.reason == .emailedTitle)
    #expect(match(bleak, [download], emailed: [bleak.id])?.confidence == .sure)
    #expect(match(bleak, [download])?.confidence == .maybe)
  }

  @Test func anEmailedTitleWithADashStillMatches() {
    let starWars = Book.fixture(id: "sw", title: "Star Wars - A New Hope", author: "George Lucas")
    let download = KindleBook.fixture(
      path: "Downloads/Items01/Star Wars - A New Hope_0123456789ABCDEF0123456789ABCDEF.kfx",
      title: "Star Wars", authors: ["A New Hope"], source: .email)
    #expect(match(starWars, [download], emailed: [starWars.id])?.confidence == .sure)
  }

  @Test func anotherEditionsASINWithTheSameTitleAndAuthorStaysAMaybe() {
    let found = match(
      moby, [.fixture(source: .sendle, asin: "SNOTHERED1")],
      editionASINs: [moby.id: ["SNEDITION1"]])
    #expect(found?.confidence == .maybe)
  }

  @Test func theStrongestMatchWinsAndEveryMatchedKindleBookIsKnown() {
    let calibre = KindleBook.fixture(path: "Melville, Herman/Moby-Dick.azw3", source: .calibre)
    let sendle = KindleBook.fixture(
      source: .sendle, asin: "SNFNYTPPHY", asinFollowsFileName: true)
    let stranger = KindleBook.fixture(path: "Dune.azw3", title: "Dune", authors: ["Frank Herbert"])
    let all = KindleMatcher.matches(
      books: [moby], editions: [:], editionASINs: [:], emailed: [],
      sameContent: [], listing: [calibre, sendle, stranger])
    #expect(all.byBook[moby.id]?.book == sendle)
    #expect(all.onKindle == [calibre.id: .maybe, sendle.id: .sure])
  }

  @Test func amongEqualMatchesSendlesOwnNameWinsOverAKeepBothCopy() {
    let own = KindleBook.fixture(source: .sendle, asin: "SNEDITION1")
    let copy = KindleBook.fixture(
      path: "Moby-Dick - Herman Melville (2).azw3", source: .sendle, asin: "SNEDITION2")
    #expect(
      match(moby, [copy, own], editionASINs: [moby.id: ["SNEDITION1", "SNEDITION2"]])?.book == own)
    let older = KindleBook.fixture(
      source: .sendle, asin: "SNFNYTPPHY", asinFollowsFileName: true)
    #expect(match(moby, [copy, older], editionASINs: [moby.id: ["SNEDITION2"]])?.book == older)
  }

  @Test func differentTitlesNeverMatch() {
    #expect(match(moby, [.fixture(title: "Dracula", authors: ["Herman Melville"])]) == nil)
  }

  let edited = Book.fixture(
    id: "moby", title: "Moby Dick Annotated", author: "H. Melville",
    original: BooksDetails(title: "Moby-Dick", author: "Herman Melville"))

  @Test func anEditedBookStillMatchesItsCopyByEditionKey() {
    let copy = KindleBook.fixture(source: .sendle, asin: "SNEDITION1")
    let found = match(edited, [copy], editionASINs: [edited.id: ["SNEDITION1"]])
    #expect(found?.reason == .editionKey)
    #expect(found?.confidence == .sure)
  }

  @Test func anEditedBookStillMatchesItsCopyByOldSendleName() {
    let copy = KindleBook.fixture(
      title: "Other", authors: [], source: .sendle, asin: "SNFNYTPPHY", asinFollowsFileName: true)
    #expect(match(edited, [copy])?.reason == .sendleName)
  }

  @Test func anEditedBookMatchesByTitleAndAuthorOfEitherSet() {
    let original = KindleBook.fixture(title: "Moby-Dick", authors: ["Herman Melville"])
    let shown = KindleBook.fixture(
      path: "Annotated.azw3", title: "Moby Dick Annotated", authors: ["H. Melville"])
    let mixed = KindleBook.fixture(
      path: "Mixed.azw3", title: "Moby Dick Annotated", authors: ["Herman Melville"])
    for copy in [original, shown, mixed] {
      let found = match(edited, [copy])
      #expect(found?.reason == .titleAndAuthor)
      #expect(found?.confidence == .maybe)
    }
  }

  @Test func anEditedBookMatchesItsEmailedCopyByEitherTitle() {
    let download = KindleBook.fixture(
      path: "Downloads/Items01/Moby-Dick_0123456789ABCDEF0123456789ABCDEF.kfx",
      title: "Moby-Dick", authors: [], source: .email)
    #expect(match(edited, [download], emailed: [edited.id])?.reason == .emailedTitle)
  }

  @Test func replaceStaysUnavailableForACopyUnderTheOldName() {
    let old = KindleBook.fixture(path: "Moby-Dick - Herman Melville.azw3")
    let new = KindleBook.fixture(path: "Moby Dick Annotated - H. Melville.azw3")
    #expect(!FileNaming.isSendlesCopy(old, of: edited))
    #expect(FileNaming.isSendlesCopy(new, of: edited))
  }

  let kindle = KindleBook.fixture(path: "Moby-Dick - Herman Melville.azw3")

  func link(_ confidence: MatchConfidence, _ reason: MatchReason) -> KindleMatch {
    KindleMatch(book: kindle, confidence: confidence, reason: reason)
  }

  @Test func aSureMatchBeatsAMaybe() {
    let matches = KindleMatches(
      byBook: [
        BookID(rawValue: "b"): link(.maybe, .titleOnly),
        BookID(rawValue: "a"): link(.sure, .sendleName),
      ], onKindle: [kindle.id: .sure])
    #expect(matches.libraryBook(for: kindle.id) == BookID(rawValue: "a"))
  }

  @Test func theStrongerReasonThenTheSmallerIDBreaksATie() {
    let byReason = KindleMatches(
      byBook: [
        BookID(rawValue: "a"): link(.sure, .titleAndAuthor),
        BookID(rawValue: "z"): link(.sure, .isbn),
      ], onKindle: [kindle.id: .sure])
    #expect(byReason.libraryBook(for: kindle.id) == BookID(rawValue: "z"))
    let byID = KindleMatches(
      byBook: [
        BookID(rawValue: "z"): link(.sure, .isbn),
        BookID(rawValue: "a"): link(.sure, .isbn),
      ], onKindle: [kindle.id: .sure])
    #expect(byID.libraryBook(for: kindle.id) == BookID(rawValue: "a"))
  }

  @Test func aMatchToAnotherKindleBookIsNotACandidate() {
    let other = KindleBook.fixture(path: "Dune.azw3", title: "Dune", authors: ["Frank Herbert"])
    let matches = KindleMatches(
      byBook: [
        BookID(rawValue: "a"): link(.maybe, .titleOnly),
        BookID(rawValue: "b"): KindleMatch(book: other, confidence: .sure, reason: .editionKey),
      ], onKindle: [kindle.id: .maybe, other.id: .sure])
    #expect(matches.libraryBook(for: kindle.id) == BookID(rawValue: "a"))
  }

  @Test func aKindleBookNoLibraryBookPointsAtHasNoLink() {
    let matches = KindleMatches(byBook: [:], onKindle: [kindle.id: .maybe])
    #expect(matches.libraryBook(for: kindle.id) == nil)
  }
}
