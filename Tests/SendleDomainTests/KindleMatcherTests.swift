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

  @Test func differentTitlesNeverMatch() {
    #expect(match(moby, [.fixture(title: "Dracula", authors: ["Herman Melville"])]) == nil)
  }
}
