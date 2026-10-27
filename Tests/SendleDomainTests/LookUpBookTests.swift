import Foundation
import SendleDomain
import SendleTestSupport
import Testing
import os

private let isbn = "9788408172277"
private let query = LookupQuery(
  title: "Los ritos del agua", author: "Eva García Sáenz", isbn: isbn, language: "es")
private let titleRequest = "title:Los ritos del agua|Eva García Sáenz|es"

private func collect(_ stream: AsyncStream<LookupProgress>) async -> [LookupProgress] {
  var all: [LookupProgress] = []
  for await progress in stream { all.append(progress) }
  return all
}

private func onlyApple(_ catalogue: FakeCatalogue) -> LookUpBook {
  LookUpBook(
    catalogues: [catalogue],
    settings: InMemorySettingsStore(AppSettings(lookupSources: [.appleBooks])))
}

/// Finds a later printing by title each time it is asked.
private final class Reprints: BookCatalogue {
  let source = LookupSource.openLibrary
  private let asked = OSAllocatedUnfairLock(initialState: 0)

  var requests: Int { asked.withLock { $0 } }

  func edition(isbn: String) async throws(LookupError) -> FoundEdition? { nil }

  func editions(title: String, author: String?, language: String?) async throws(LookupError)
    -> [FoundEdition]
  {
    let count = asked.withLock { asked in
      asked += 1
      return asked
    }
    return [.fixture(year: "\(2016 + count)")]
  }

  func image(at url: URL) async throws(LookupError) -> Data? { nil }
}

@Suite(.timeLimit(.minutes(1)))
struct LookUpBookTests {
  @Test func asksEveryEnabledSourceAtOnce() async {
    let open = FakeCatalogue(.openLibrary, byISBN: [isbn: .success(.fixture())])
    let apple = FakeCatalogue(.appleBooks)
    let google = FakeCatalogue(.googleBooks)
    let use = LookUpBook(catalogues: [open, google, apple], settings: InMemorySettingsStore())
    let last = await collect(use.lookUp(query)).last
    #expect(last?.sources == [.openLibrary, .appleBooks])
    #expect(last?.result(for: .openLibrary) == .edition(.fixture()))
    #expect(google.requests.isEmpty)
    #expect(last?.isFinished == true)
  }

  @Test func availableListsTheCataloguesInOrder() {
    let use = LookUpBook(
      catalogues: [FakeCatalogue(.appleBooks), FakeCatalogue(.openLibrary)],
      settings: InMemorySettingsStore())
    #expect(use.available == [.openLibrary, .appleBooks])
  }

  @Test func noSourceWaitsForAnother() async {
    let gate = Signal()
    let open = FakeCatalogue(.openLibrary, byISBN: [isbn: .success(.fixture())], gate: gate)
    let apple = FakeCatalogue(.appleBooks, gate: gate)
    let use = LookUpBook(catalogues: [open, apple], settings: InMemorySettingsStore())
    let lookup = Task { await collect(use.lookUp(query)) }
    #expect(await eventually { open.requests.count == 1 && apple.requests.count == 1 })
    await gate.fire()
    #expect(await lookup.value.last?.isFinished == true)
  }

  @Test func yieldsEachAnswerAsItArrives() async {
    let gate = Signal()
    let open = FakeCatalogue(.openLibrary, byISBN: [isbn: .success(.fixture())], gate: gate)
    let apple = FakeCatalogue(.appleBooks, byISBN: [isbn: .failure(.offline)])
    let use = LookUpBook(catalogues: [open, apple], settings: InMemorySettingsStore())
    var updates = use.lookUp(query).makeAsyncIterator()

    let first = await updates.next()
    #expect(first?.isbnAnswers == [.appleBooks: .failed(.offline)])
    #expect(first?.isFinished == false)

    await gate.fire()
    let second = await updates.next()
    #expect(second?.isbnAnswers[.openLibrary] == .found([.fixture()]))
    #expect(second?.isFinished == false)
    #expect(await updates.next()?.isFinished == true)
    #expect(await updates.next() == nil)
  }

  @Test(arguments: [
    FoundEdition.fixture(.appleBooks, title: "Cooking with Gas", author: "Ann Other"),
    FoundEdition.fixture(.appleBooks, author: "Ann Other"),
    FoundEdition.fixture(.appleBooks, title: "Cooking with Gas"),
    FoundEdition.fixture(.appleBooks, title: nil),
  ])
  func appleMatchNeedsTitleAndAuthor(_ wrong: FoundEdition) async {
    let use = onlyApple(FakeCatalogue(.appleBooks, byISBN: [isbn: .success(wrong)]))
    #expect(await collect(use.lookUp(query)).last?.isbnAnswers[.appleBooks] == .notFound)
  }

  @Test(arguments: [
    "Los ritos del agua (La Ciudad Blanca 2)", "Los ritos del agua: La Ciudad Blanca 2",
    "LOS RITOS DEL AGUA",
  ])
  func appleTitleWithSeriesStillMatches(_ title: String) async {
    let found = FoundEdition.fixture(.appleBooks, title: title, author: "Eva García Sáenz")
    let use = onlyApple(FakeCatalogue(.appleBooks, byISBN: [isbn: .success(found)]))
    #expect(await collect(use.lookUp(query)).last?.isbnAnswers[.appleBooks] == .found([found]))
  }

  @Test func appleMatchWithoutAnAuthorNeedsOnlyTheTitle() async {
    let found = FoundEdition.fixture(.appleBooks, author: "Ann Other")
    let use = onlyApple(FakeCatalogue(.appleBooks, byISBN: [isbn: .success(found)]))
    let anonymous = LookupQuery(title: query.title, author: nil, isbn: isbn, language: "es")
    #expect(await collect(use.lookUp(anonymous)).last?.isbnAnswers[.appleBooks] == .found([found]))
  }

  @Test func unknownISBNMovesOnToTitleAndAuthor() async {
    let newer = FoundEdition.fixture(year: "2019")
    let english = FoundEdition.fixture(isbn: nil, language: "en")
    let open = FakeCatalogue(.openLibrary, byTitle: .success([english, newer]))
    let use = LookUpBook(catalogues: [open], settings: InMemorySettingsStore())
    let all = await collect(use.lookUp(query))
    #expect(all.map(\.method) == [.isbn, .titleAndAuthor, .titleAndAuthor, .titleAndAuthor])
    #expect(all.map(\.isFinished) == [false, false, false, true])
    #expect(all.last?.method == .titleAndAuthor)
    #expect(all.last?.titleAnswers[.openLibrary] == .found([newer, english]))
    #expect(open.requests == ["isbn:\(isbn)", titleRequest])
  }

  @Test func googleBooksListKeepsItsOwnOrder() async {
    let listed = (0..<12).map {
      FoundEdition.fixture(.googleBooks, year: "\(2000 + $0)", isbn: nil)
    }
    let google = FakeCatalogue(.googleBooks, byTitle: .success(listed))
    let use = LookUpBook(
      catalogues: [google],
      settings: InMemorySettingsStore(AppSettings(lookupSources: [.googleBooks])))
    let noISBN = LookupQuery(title: query.title, author: query.author, isbn: nil, language: "es")
    let last = await collect(use.lookUp(noISBN)).last
    #expect(last?.titleAnswers[.googleBooks] == .found(Array(listed.prefix(10))))
  }

  @Test func everySourceFailingStopsAtTheISBN() async {
    let open = FakeCatalogue(.openLibrary, byISBN: [isbn: .failure(.offline)])
    let apple = FakeCatalogue(.appleBooks, byISBN: [isbn: .failure(.offline)])
    let use = LookUpBook(catalogues: [open, apple], settings: InMemorySettingsStore())
    let last = await collect(use.lookUp(query)).last
    #expect(last?.method == .isbn)
    #expect(last?.isFinished == true)
    #expect(last?.result(for: .openLibrary) == .failed(.offline))
    #expect(open.requests == ["isbn:\(isbn)"])
    #expect(apple.requests == ["isbn:\(isbn)"])
  }

  @Test func noISBNSearchesByTitleOnly() async {
    let open = FakeCatalogue(.openLibrary, byTitle: .success([.fixture()]))
    let apple = FakeCatalogue(.appleBooks, byTitle: .failure(.timedOut))
    let use = LookUpBook(catalogues: [open, apple], settings: InMemorySettingsStore())
    let noISBN = LookupQuery(title: query.title, author: query.author, isbn: nil, language: "es")
    let all = await collect(use.lookUp(noISBN))
    #expect(all.allSatisfy { $0.method == .titleAndAuthor })
    #expect(all.last?.result(for: .openLibrary) == .editions([.fixture()]))
    #expect(all.last?.result(for: .appleBooks) == .failed(.timedOut))
    #expect(all.last?.isFinished == true)
    #expect(open.requests == [titleRequest])
    #expect(apple.requests == [titleRequest])
  }

  @Test func noEnabledSourceFinishesAtOnce() async {
    let open = FakeCatalogue(.openLibrary)
    let use = LookUpBook(
      catalogues: [open], settings: InMemorySettingsStore(AppSettings(lookupSources: [])))
    let all = await collect(use.lookUp(query))
    #expect(all.count == 1)
    #expect(all.first?.isFinished == true)
    #expect(all.first?.sources == [])
    #expect(open.requests.isEmpty)
  }

  @Test func answersAreCachedButFailuresAreNot() async {
    let open = FakeCatalogue(.openLibrary, byISBN: [isbn: .success(.fixture())])
    let apple = FakeCatalogue(.appleBooks, byISBN: [isbn: .failure(.offline)])
    let use = LookUpBook(catalogues: [open, apple], settings: InMemorySettingsStore())
    let copy = use
    _ = await collect(use.lookUp(query))
    let again = await collect(copy.lookUp(query)).last
    #expect(again?.result(for: .openLibrary) == .edition(.fixture()))
    #expect(open.requests == ["isbn:\(isbn)"])
    #expect(apple.requests == ["isbn:\(isbn)", "isbn:\(isbn)"])
  }

  @Test func notFoundAndEditionListsAreCachedPerRequest() async {
    let apple = FakeCatalogue(.appleBooks, byTitle: .success([.fixture(.appleBooks)]))
    let use = onlyApple(apple)
    _ = await collect(use.lookUp(query))
    _ = await collect(use.lookUp(query))
    let english = LookupQuery(title: query.title, author: query.author, isbn: isbn, language: "en")
    _ = await collect(use.lookUp(english))
    #expect(
      apple.requests == [
        "isbn:\(isbn)", titleRequest, "title:Los ritos del agua|Eva García Sáenz|en",
      ])
  }

  @Test func refreshingAsksAgainAndKeepsTheNewAnswer() async {
    let reprints = Reprints()
    let use = LookUpBook(catalogues: [reprints], settings: InMemorySettingsStore())
    let noISBN = LookupQuery(title: query.title, author: query.author, isbn: nil, language: "es")
    let first = await collect(use.lookUp(noISBN)).last
    #expect(first?.result(for: .openLibrary) == .editions([.fixture(year: "2017")]))

    let refreshed = await collect(use.lookUp(noISBN, refreshing: true)).last
    #expect(refreshed?.result(for: .openLibrary) == .editions([.fixture(year: "2018")]))
    #expect(reprints.requests == 2)

    let kept = await collect(use.lookUp(noISBN)).last
    #expect(kept?.result(for: .openLibrary) == .editions([.fixture(year: "2018")]))
    #expect(reprints.requests == 2)
  }

  @Test func endingTheStreamCancelsTheLookup() async throws {
    let log = FakeActivityLog()
    let open = FakeCatalogue(.openLibrary, gate: Signal())
    let use = LookUpBook(catalogues: [open], settings: InMemorySettingsStore(), log: log)
    let lookup = Task { await collect(use.lookUp(query)) }
    #expect(await eventually { open.requests.count == 1 })

    lookup.cancel()

    #expect(await lookup.value.isEmpty)
    #expect(await eventually { open.cancelledRequests == ["isbn:\(isbn)"] })
    try await Task.sleep(for: .milliseconds(50))
    #expect(open.requests == ["isbn:\(isbn)"])
    #expect(log.entries().isEmpty)
  }

  @Test func aSourceSlowerThanTheDeadlineTimesOut() async {
    let open = FakeCatalogue(
      .openLibrary, byISBN: [isbn: .success(.fixture())], byTitle: .success([.fixture()]),
      gate: Signal())
    let use = LookUpBook(
      catalogues: [open], settings: InMemorySettingsStore(), deadline: .milliseconds(50))

    let byISBN = await collect(use.lookUp(query)).last
    #expect(byISBN?.isbnAnswers[.openLibrary] == .failed(.timedOut))
    #expect(byISBN?.isFinished == true)

    let noISBN = LookupQuery(title: query.title, author: query.author, isbn: nil, language: "es")
    let byTitle = await collect(use.lookUp(noISBN)).last
    #expect(byTitle?.titleAnswers[.openLibrary] == .failed(.timedOut))
    #expect(byTitle?.isFinished == true)

    #expect(open.cancelledRequests == ["isbn:\(isbn)", titleRequest])
  }

  @Test func aRefineSlowerThanTheDeadlineKeepsThePickedEdition() async {
    let open = FakeCatalogue(.openLibrary, byISBN: [isbn: .success(.fixture())], gate: Signal())
    let use = LookUpBook(
      catalogues: [open], settings: InMemorySettingsStore(), deadline: .milliseconds(50))
    let picked = FoundEdition.fixture(year: nil)

    #expect(await use.refine(picked) == picked)
    #expect(await use.refine(picked) == picked)

    #expect(open.requests == ["isbn:\(isbn)", "isbn:\(isbn)"])
    #expect(open.cancelledRequests == ["isbn:\(isbn)", "isbn:\(isbn)"])
  }

  @Test func refineAsksByISBN() async {
    let open = FakeCatalogue(.openLibrary, byISBN: [isbn: .success(.fixture())])
    let use = LookUpBook(catalogues: [open], settings: InMemorySettingsStore())
    #expect(await use.refine(.fixture(year: nil)) == .fixture())
    #expect(await use.refine(.fixture(year: nil)) == .fixture())
    #expect(open.requests == ["isbn:\(isbn)"])
  }

  @Test func refineKeepsTheEditionWithoutAnAnswer() async {
    let other = "9780593311145"
    let open = FakeCatalogue(.openLibrary, byISBN: [isbn: .failure(.offline)])
    let use = LookUpBook(catalogues: [open], settings: InMemorySettingsStore())
    let picked = FoundEdition.fixture(year: nil)
    #expect(await use.refine(picked) == picked)
    #expect(await use.refine(.fixture(isbn: other)) == .fixture(isbn: other))
    #expect(await use.refine(.fixture(isbn: nil)) == .fixture(isbn: nil))
    #expect(await use.refine(.fixture(.googleBooks)) == .fixture(.googleBooks))
    #expect(open.requests == ["isbn:\(isbn)", "isbn:\(other)"])
  }

  @Test func imageIsNilOnFailure() async {
    let cover = URL(filePath: "/covers/1.jpg")
    let data = Data([1, 2, 3])
    let open = FakeCatalogue(.openLibrary, images: [cover: data])
    let use = LookUpBook(catalogues: [open], settings: InMemorySettingsStore())
    #expect(await use.image(at: cover, from: .openLibrary) == data)
    #expect(await use.image(at: URL(filePath: "/covers/2.jpg"), from: .openLibrary) == nil)
    #expect(await use.image(at: cover, from: .googleBooks) == nil)
  }

  @Test func logsNeverHoldTheQuery() async {
    let log = FakeActivityLog()
    let open = FakeCatalogue(.openLibrary, byISBN: [isbn: .success(.fixture())])
    let use = LookUpBook(catalogues: [open], settings: InMemorySettingsStore(), log: log)
    _ = await collect(use.lookUp(query))
    #expect(log.messages(in: .lookup).contains("Open Library by ISBN: found"))
    #expect(!log.summary.contains { $0.contains("ritos") || $0.contains("Eva") })
  }

  @Test func logsEachSourcesAnswer() async {
    let log = FakeActivityLog()
    let editions = ["9788408203119", "9780593311145", nil].map { FoundEdition.fixture(isbn: $0) }
    let open = FakeCatalogue(.openLibrary, byTitle: .success(editions))
    let apple = FakeCatalogue(
      .appleBooks, byISBN: [isbn: .failure(.timedOut)],
      byTitle: .success([.fixture(.appleBooks)]))
    let use = LookUpBook(catalogues: [open, apple], settings: InMemorySettingsStore(), log: log)
    _ = await collect(use.lookUp(query))
    #expect(
      Set(log.summary) == [
        "info LOOKUP Open Library by ISBN: didn't find it",
        "warning LOOKUP Apple Books by ISBN: timed out",
        "info LOOKUP Open Library by title and author: 3 editions",
        "info LOOKUP Apple Books by title and author: 1 edition",
      ])
  }
}
