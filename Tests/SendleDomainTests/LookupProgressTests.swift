import SendleDomain
import Testing

private let dune = FoundEdition(source: .openLibrary, title: "Dune", year: "1990")
private let apple = FoundEdition(source: .appleBooks, title: "Dune")

@Suite(.timeLimit(.minutes(1)))
struct LookupProgressTests {
  @Test func waitsForEarlierSourcesBeforeShowingALaterOne() {
    var progress = LookupProgress(sources: [.openLibrary, .appleBooks], method: .isbn)
    progress.isbnAnswers[.appleBooks] = .found([apple])
    #expect(progress.shownSource == nil)
    progress.isbnAnswers[.openLibrary] = .notFound
    #expect(progress.shownSource == .appleBooks)
  }

  @Test func firstSourceInOrderWins() {
    let progress = LookupProgress(
      sources: [.openLibrary, .appleBooks],
      method: .isbn,
      isbnAnswers: [.openLibrary: .found([dune]), .appleBooks: .found([apple])])
    #expect(progress.shownSource == .openLibrary)
    #expect(progress.result(for: .openLibrary) == .edition(dune))
    #expect(!progress.needsEditionList)
  }

  @Test func appleOnlyISBNMatchNeedsTheEditionList() {
    let progress = LookupProgress(
      sources: [.openLibrary, .appleBooks],
      method: .isbn,
      isbnAnswers: [.openLibrary: .notFound, .appleBooks: .found([apple])])
    #expect(progress.needsEditionList)
  }

  @Test func everySourceFailingNeedsNoList() {
    let progress = LookupProgress(
      sources: [.openLibrary, .appleBooks],
      method: .isbn,
      isbnAnswers: [.openLibrary: .failed(.offline), .appleBooks: .failed(.offline)])
    #expect(!progress.needsEditionList)
    #expect(progress.shownSource == nil)
  }

  @Test func titleSearchShowsListsButKeepsAppleISBNMatch() {
    let progress = LookupProgress(
      sources: [.openLibrary, .appleBooks],
      method: .titleAndAuthor,
      isbnAnswers: [.openLibrary: .notFound, .appleBooks: .found([apple])],
      titleAnswers: [.openLibrary: .found([dune])])
    #expect(progress.result(for: .openLibrary) == .editions([dune]))
    #expect(progress.result(for: .appleBooks) == .edition(apple))
    #expect(progress.shownSource == .openLibrary)
  }

  @Test func emptyListIsNotFound() {
    let progress = LookupProgress(
      sources: [.openLibrary],
      method: .titleAndAuthor,
      titleAnswers: [.openLibrary: .found([])])
    #expect(progress.result(for: .openLibrary) == .notFound)
  }

  @Test func noListWhileASourceIsStillAsking() {
    let progress = LookupProgress(
      sources: [.openLibrary, .appleBooks],
      method: .isbn,
      isbnAnswers: [.openLibrary: .notFound])
    #expect(!progress.needsEditionList)
    #expect(progress.result(for: .appleBooks) == .asking)
  }

  @Test func nothingFoundByISBNNeedsTheEditionList() {
    let progress = LookupProgress(
      sources: [.openLibrary, .appleBooks],
      method: .isbn,
      isbnAnswers: [.openLibrary: .notFound, .appleBooks: .failed(.timedOut)])
    #expect(progress.needsEditionList)
  }

  @Test func titleSearchNeedsNoList() {
    let progress = LookupProgress(
      sources: [.openLibrary],
      method: .titleAndAuthor,
      isbnAnswers: [.openLibrary: .notFound])
    #expect(!progress.needsEditionList)
  }
}
