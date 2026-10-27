import AppKit
import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing
import os

/// A lookup the test drives: each search hands its stream's continuation to the test, and
/// refines and images answer from what the script was given.
private final class ScriptedLookup: Sendable {
  private struct State {
    var queries: [LookupQuery] = []
    var streams: [AsyncStream<LookupProgress>.Continuation] = []
    var ended: Set<Int> = []
    var imageRequests: [URL] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let refined: [FoundEdition: FoundEdition]
  /// A refine of an edition with a gate waits for it to fire.
  private let gates: [FoundEdition: Signal]
  private let images: [URL: Data]
  /// Likewise an image.
  private let imageGates: [URL: Signal]

  init(
    refined: [FoundEdition: FoundEdition] = [:], gates: [FoundEdition: Signal] = [:],
    images: [URL: Data] = [:], imageGates: [URL: Signal] = [:]
  ) {
    self.refined = refined
    self.gates = gates
    self.images = images
    self.imageGates = imageGates
  }

  func lookup(sources: [LookupSource] = [.openLibrary, .appleBooks]) -> DetailsLookup {
    DetailsLookup(
      sources: sources,
      search: { query in
        let (stream, continuation) = AsyncStream.makeStream(of: LookupProgress.self)
        let index = self.state.withLock { state in
          state.queries.append(query)
          state.streams.append(continuation)
          return state.streams.count - 1
        }
        continuation.onTermination = { _ in self.state.withLock { _ = $0.ended.insert(index) } }
        return stream
      },
      refine: { edition in
        await self.gates[edition]?.wait()
        return self.refined[edition] ?? edition
      },
      image: { url, _ in
        self.state.withLock { $0.imageRequests.append(url) }
        await self.imageGates[url]?.wait()
        return self.images[url]
      })
  }

  var queries: [LookupQuery] { state.withLock { $0.queries } }
  var imageRequests: [URL] { state.withLock { $0.imageRequests } }

  /// Whether the `search`th search's stream has ended, as cancelling it ends it.
  func hasEnded(_ search: Int) -> Bool { state.withLock { $0.ended.contains(search) } }

  /// Feeds the `search`th search, the latest by default.
  func send(_ progress: LookupProgress, to search: Int? = nil) {
    let continuation = state.withLock { $0.streams[search ?? $0.streams.count - 1] }
    continuation.yield(progress)
  }
}

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct BookDetailsLookupTests {
  private let eva = Book.fixture(
    id: "eva", title: "Los ritos del agua", author: "Eva Garcia Saenz", language: "es")
  private let isbn = "9788408172277"
  /// Differs from the sheet in author and year.
  private let openLibrary = FoundEdition.fixture()
  /// Agrees with the sheet in everything it has.
  private let apple = FoundEdition.fixture(.appleBooks, author: "Eva Garcia Saenz", year: nil)
  private let coverURL: URL

  init() throws {
    coverURL = try #require(URL(string: "https://covers.example/1-L.jpg"))
  }

  /// `openLibrary` with a cover.
  private var withCover: FoundEdition {
    var edition = openLibrary
    edition.cover = coverURL
    return edition
  }

  /// `library` holds the other books, and `saved` records what saving saves.
  private func sheet(
    _ book: Book? = nil, library: [Book] = [],
    fileValues: Edition? = Edition(isbn: "9788408172277", year: "2016"),
    saved: Recorder<BookDetailsDraft>? = nil, lookup: DetailsLookup?
  ) -> BookDetailsViewModel {
    let book = book ?? eva
    return BookDetailsViewModel(
      book: book, library: [book] + library, fileValues: fileValues, authorSort: .surname,
      lastSend: nil, now: Date(timeIntervalSince1970: 1_800_000_000), zone: .gmt,
      save: { (draft: BookDetailsDraft) async throws(EditDetailsError) in
        await saved?.record(draft)
      }, lookup: lookup)
  }

  /// Starts a lookup whose first answer is Open Library's `edition`, and waits for it to show.
  private func lookUp(
    _ sheet: BookDetailsViewModel, _ script: ScriptedLookup, finding edition: FoundEdition
  ) async -> Bool {
    sheet.lookUp()
    script.send(progress(isbn: [.openLibrary: .found([edition])]))
    return await eventually { sheet.shownEdition == edition }
  }

  private func progress(
    _ method: LookupMethod = .isbn, sources: [LookupSource] = [.openLibrary, .appleBooks],
    isbn: [LookupSource: SourceAnswer] = [:], title: [LookupSource: SourceAnswer] = [:],
    finished: Bool = false
  ) -> LookupProgress {
    LookupProgress(
      sources: sources, method: method, isbnAnswers: isbn, titleAnswers: title,
      isFinished: finished)
  }

  /// Three editions found by title, the first two with the same thumbnail.
  private var editions: [FoundEdition] {
    let thumbnail = URL(string: "https://covers.example/1-S.jpg")
    var first = FoundEdition.fixture()
    first.thumbnail = thumbnail
    var second = FoundEdition.fixture(year: "2019", isbn: "9788408203119")
    second.thumbnail = thumbnail
    var third = FoundEdition.fixture(title: "The Water Rituals", year: "2021", language: "en")
    third.thumbnail = URL(string: "https://covers.example/3-S.jpg")
    return [first, second, third]
  }

  /// Lets tasks already waiting for the main actor run, for checks that something didn't happen.
  private func settle() async {
    try? await Task.sleep(for: .milliseconds(50))
  }

  @Test func queryUsesWhatTheFieldsShow() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    sheet.title = " "
    sheet.isbn = ""
    sheet.author = "  Eva García Sáenz "
    sheet.lookUp()

    #expect(
      script.queries == [
        LookupQuery(
          title: "Los ritos del agua", author: "Eva García Sáenz", isbn: isbn, language: "es")
      ])
    #expect(sheet.progress == progress())
    #expect(sheet.banner == .searching(.isbn))
    #expect(sheet.banner?.text == "Looking up by ISBN…")

    sheet.isbn = "9788408172270"
    sheet.language = "pt_BR"
    sheet.lookUp()
    #expect(script.queries.last?.isbn == nil)
    #expect(script.queries.last?.language == "pt")
    #expect(sheet.progress == progress(.titleAndAuthor))
  }

  @Test func waitsThenShowsTheFirstSourceInOrder() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    sheet.lookUp()

    let onlyApple = progress(isbn: [.appleBooks: .found([apple])])
    script.send(onlyApple)
    #expect(await eventually { sheet.progress == onlyApple })
    #expect(sheet.shownSource == nil)
    #expect(sheet.shownEdition == nil)
    #expect(sheet.banner == .searching(.isbn))

    let both = progress(isbn: [.appleBooks: .found([apple]), .openLibrary: .found([openLibrary])])
    script.send(both)
    #expect(await eventually { sheet.progress == both })
    #expect(sheet.shownSource == .openLibrary)
    #expect(sheet.shownEdition == openLibrary)
    #expect(sheet.differences == 2)
    #expect(sheet.banner == .found(.openLibrary, differences: 2))
    #expect(sheet.banner?.text == "Found on Open Library")
    #expect(!sheet.isPickingEdition)
  }

  @Test func showingASourceSwitchesTheDetails() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup(sources: LookupSource.allCases))
    sheet.lookUp()
    let found = progress(
      sources: LookupSource.allCases,
      isbn: [
        .openLibrary: .found([openLibrary]), .googleBooks: .notFound, .appleBooks: .found([apple]),
      ])
    script.send(found)
    #expect(await eventually { sheet.progress == found })

    sheet.show(.appleBooks)
    #expect(sheet.shownSource == .appleBooks)
    #expect(sheet.shownEdition == apple)
    #expect(sheet.banner == .found(.appleBooks, differences: 0))

    // A source with nothing to show keeps the details in view.
    sheet.show(.googleBooks)
    #expect(sheet.shownSource == .appleBooks)

    sheet.show(.openLibrary)
    #expect(sheet.shownEdition == openLibrary)
    #expect(sheet.banner == .found(.openLibrary, differences: 2))
  }

  @Test func pressingAgainIgnoresTheOlderLookup() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    sheet.lookUp()
    let first = progress(isbn: [.openLibrary: .found([openLibrary])])
    script.send(first, to: 0)
    #expect(await eventually { sheet.progress == first })
    sheet.year = "2017"

    // The older lookup's answer comes in just as 🌐 is pressed again.
    let late = progress(isbn: [.openLibrary: .notFound, .appleBooks: .notFound], finished: true)
    script.send(late, to: 0)
    sheet.lookUp()
    await settle()

    #expect(sheet.progress == progress())
    #expect(sheet.year == "2017")
    #expect(await eventually { script.hasEnded(0) })
    #expect(!script.hasEnded(1))

    let second = progress(isbn: [.appleBooks: .found([apple])])
    script.send(second, to: 1)
    #expect(await eventually { sheet.progress == second })
  }

  @Test func cancelledLookupIgnoresLateProgress() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    sheet.lookUp()
    let first = progress(isbn: [.openLibrary: .found([openLibrary])])
    script.send(first)
    #expect(await eventually { sheet.progress == first })

    script.send(progress(isbn: [.openLibrary: .found([openLibrary])], finished: true))
    sheet.cancelLookup()
    await settle()

    #expect(sheet.progress == nil)
    #expect(sheet.banner == nil)
    #expect(sheet.shownEdition == nil)
    #expect(sheet.sourceMenu.isEmpty)
    #expect(await eventually { script.hasEnded(0) })
    #expect(sheet.title == "Los ritos del agua" && sheet.author == "Eva Garcia Saenz")
    #expect(sheet.year == "2016" && sheet.isbn == isbn && sheet.language == "es")
  }

  @Test func titleSearchOpensTheListOnce() async {
    let script = ScriptedLookup()
    let sheet = sheet(fileValues: nil, lookup: script.lookup())
    sheet.lookUp()
    #expect(script.queries.first?.isbn == nil)
    #expect(sheet.banner == .searching(.titleAndAuthor))
    #expect(sheet.banner?.text == "Looking up by title and author…")

    let listed = progress(.titleAndAuthor, title: [.openLibrary: .found(editions)])
    script.send(listed)
    #expect(await eventually { sheet.isPickingEdition })
    #expect(sheet.editionRows.map(\.edition) == editions)
    #expect(sheet.editionRows.map(\.id) == [0, 1, 2])
    #expect(sheet.shownEdition == nil)
    #expect(sheet.banner == .editions(.openLibrary, hadISBN: false))
    #expect(sheet.banner?.text == "No ISBN, so searched Open Library by title and author")

    sheet.pick(sheet.editionRows[1])
    #expect(!sheet.isPickingEdition)
    #expect(sheet.editionRows.isEmpty)
    let answered = progress(
      .titleAndAuthor, title: [.openLibrary: .found(editions), .appleBooks: .notFound],
      finished: true)
    script.send(answered)
    #expect(await eventually { sheet.progress == answered })
    #expect(!sheet.isPickingEdition)
    #expect(sheet.shownEdition == editions[1])

    // ▾ brings the list back; skipping it ends the lookup.
    sheet.show(.openLibrary)
    #expect(sheet.isPickingEdition)
    #expect(sheet.shownEdition == nil)
    sheet.skipEditionList()
    #expect(!sheet.isPickingEdition)
    #expect(sheet.progress == nil && sheet.banner == nil)
    #expect(await eventually { script.hasEnded(0) })
    #expect(sheet.year == "" && sheet.isbn == "")
    #expect(sheet.title == "Los ritos del agua" && sheet.author == "Eva Garcia Saenz")
  }

  @Test func anUnknownISBNListsEditionsByTitle() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    sheet.lookUp()
    let listed = progress(
      .titleAndAuthor, isbn: [.openLibrary: .notFound, .appleBooks: .notFound],
      title: [.openLibrary: .found(editions)])
    script.send(listed)

    #expect(await eventually { sheet.isPickingEdition })
    #expect(sheet.banner == .editions(.openLibrary, hadISBN: true))
    #expect(
      sheet.banner?.text
        == "No source knows this ISBN, so searched Open Library by title and author")
  }

  @Test func pickingShowsTheRefinedEdition() async {
    let first = editions[0]
    let second = editions[1]
    var refinedFirst = first
    refinedFirst.publisher = "Planeta"
    var refinedSecond = second
    refinedSecond.publisher = "Booket"
    let firstGate = Signal()
    let secondGate = Signal()
    let script = ScriptedLookup(
      refined: [first: refinedFirst, second: refinedSecond],
      gates: [first: firstGate, second: secondGate])
    let sheet = sheet(fileValues: nil, lookup: script.lookup())
    sheet.lookUp()
    script.send(progress(.titleAndAuthor, title: [.openLibrary: .found(editions)]))
    #expect(await eventually { sheet.isPickingEdition })

    sheet.pick(sheet.editionRows[0])
    #expect(sheet.shownEdition == first)
    #expect(sheet.banner == .found(.openLibrary, differences: 3))
    await firstGate.fire()
    #expect(await eventually { sheet.shownEdition == refinedFirst })

    // A refine that ends after the pick changed is dropped.
    sheet.show(.openLibrary)
    sheet.pick(sheet.editionRows[1])
    #expect(sheet.shownEdition == second)
    sheet.show(.openLibrary)
    sheet.pick(sheet.editionRows[0])
    #expect(await eventually { sheet.shownEdition == refinedFirst })
    await secondGate.fire()
    await settle()
    #expect(sheet.shownEdition == refinedFirst)
  }

  @Test func sourceMenuStatuses() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup(sources: LookupSource.allCases))
    #expect(sheet.sourceMenu.isEmpty)
    sheet.lookUp()
    #expect(sheet.sourceMenu.map(\.status) == ["Asking…", "Asking…", "Asking…"])

    let asking = progress(
      sources: LookupSource.allCases,
      isbn: [.openLibrary: .found([openLibrary]), .googleBooks: .failed(.missingKey)])
    script.send(asking)
    #expect(await eventually { sheet.progress == asking })
    #expect(sheet.sourceMenu.map(\.source) == LookupSource.allCases)
    #expect(
      sheet.sourceMenu.map(\.status) == ["2 differences", "Needs your API key", "Asking…"])

    let answered = progress(
      sources: LookupSource.allCases,
      isbn: [
        .openLibrary: .found([.fixture(year: "2016")]), .googleBooks: .failed(.timedOut),
        .appleBooks: .notFound,
      ], finished: true)
    script.send(answered)
    #expect(await eventually { sheet.progress == answered })
    #expect(
      sheet.sourceMenu.map(\.status) == [
        "1 difference", "Couldn't reach it", "Didn't find this book",
      ])

    let listed = progress(
      .titleAndAuthor, sources: LookupSource.allCases, isbn: [.appleBooks: .found([apple])],
      title: [.openLibrary: .found(editions), .googleBooks: .failed(.offline)])
    script.send(listed)
    #expect(await eventually { sheet.progress == listed })
    #expect(
      sheet.sourceMenu.map(\.status) == [
        "3 editions", "Couldn't reach it", "Agrees with everything",
      ])
  }

  @Test func everySourceAgreesSaysSo() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    sheet.lookUp()
    let agreeing = FoundEdition.fixture(author: "Eva Garcia Saenz", year: "2016")
    let found = [
      LookupSource.openLibrary: SourceAnswer.found([agreeing]), .appleBooks: .found([apple]),
    ]
    script.send(progress(isbn: found))
    #expect(await eventually { sheet.shownEdition == agreeing })
    #expect(sheet.banner == .found(.openLibrary, differences: 0))

    script.send(progress(isbn: found, finished: true))
    #expect(await eventually { sheet.progress?.isFinished == true })
    #expect(sheet.banner == .allAgree([.openLibrary, .appleBooks]))
    #expect(sheet.banner?.text == "Open Library and Apple Books agree with everything here.")

    #expect(
      LookupBanner.allAgree([.openLibrary]).text == "Open Library agrees with everything here.")
    #expect(
      LookupBanner.allAgree(LookupSource.allCases).text
        == "Open Library, Google Books and Apple Books agree with everything here.")
  }

  @Test func oneDifferenceKeepsTheFoundBanner() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    sheet.lookUp()
    let finished = progress(
      isbn: [.openLibrary: .found([.fixture(year: "2016")]), .appleBooks: .found([apple])],
      finished: true)
    script.send(finished)
    #expect(await eventually { sheet.progress == finished })
    #expect(sheet.banner == .found(.openLibrary, differences: 1))
  }

  @Test func everySourceOfflineSaysSo() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    sheet.lookUp()
    let offline = progress(
      isbn: [.openLibrary: .failed(.offline), .appleBooks: .failed(.offline)], finished: true)
    script.send(offline)

    #expect(await eventually { sheet.progress == offline })
    #expect(sheet.banner == .offline)
    #expect(sheet.banner?.text == "You're offline. Connect and try 🌐 again.")
  }

  @Test func failuresAndNothingFound() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    sheet.lookUp()
    let failed = progress(
      isbn: [.openLibrary: .failed(.timedOut), .appleBooks: .failed(.offline)], finished: true)
    script.send(failed)
    #expect(await eventually { sheet.progress == failed })
    #expect(sheet.banner == .unreachable([.openLibrary, .appleBooks]))

    sheet.lookUp()
    let nothing = progress(
      .titleAndAuthor, isbn: [.openLibrary: .notFound, .appleBooks: .notFound],
      title: [.openLibrary: .found([]), .appleBooks: .failed(.offline)], finished: true)
    script.send(nothing)
    #expect(await eventually { sheet.progress == nothing })
    #expect(sheet.banner == .nothingFound)
    #expect(sheet.banner?.text == "No source knows this book.")
  }

  @Test func unreachableNamesTheSources() {
    #expect(
      LookupBanner.unreachable([.openLibrary, .appleBooks]).text
        == "Couldn't reach Open Library or Apple Books. Try again later.")
    #expect(
      LookupBanner.unreachable(LookupSource.allCases).text
        == "Couldn't reach Open Library, Google Books or Apple Books. Try again later.")
    #expect(
      LookupBanner.unreachable([.googleBooks]).text
        == "Couldn't reach Google Books. Try again later.")
  }

  @Test func aPDFCountsOnlyTitleAndAuthor() async {
    let script = ScriptedLookup()
    let pdf = Book.fixture(
      id: "pdf", title: "Los ritos del agua", author: "Eva Garcia Saenz", language: "en",
      format: .pdf)
    let sheet = sheet(pdf, lookup: script.lookup())
    sheet.lookUp()
    script.send(progress(isbn: [.openLibrary: .found([openLibrary])]))

    #expect(await eventually { sheet.shownEdition == openLibrary })
    #expect(sheet.differences == 1)
    #expect(sheet.sourceMenu.first?.status == "1 difference")
  }

  @Test func thumbnailsLoadOncePerURL() async throws {
    let small = try #require(URL(string: "https://covers.example/1-S.jpg"))
    let other = try #require(URL(string: "https://covers.example/3-S.jpg"))
    let script = ScriptedLookup(images: [small: Data("1".utf8), other: Data("3".utf8)])
    let sheet = sheet(fileValues: nil, lookup: script.lookup())
    sheet.lookUp()
    #expect(sheet.thumbnails.isEmpty)
    script.send(progress(.titleAndAuthor, title: [.openLibrary: .found(editions)]))

    #expect(await eventually { sheet.thumbnails.count == 2 })
    #expect(sheet.thumbnails == [small: Data("1".utf8), other: Data("3".utf8)])
    sheet.show(.openLibrary)
    let answered = progress(
      .titleAndAuthor, title: [.openLibrary: .found(editions), .appleBooks: .notFound])
    script.send(answered)
    #expect(await eventually { sheet.progress == answered })
    await settle()
    #expect(
      script.imageRequests.sorted { $0.absoluteString < $1.absoluteString } == [small, other])
  }

  @Test func appleRowsSayEbook() {
    let row = EditionRow(id: 0, edition: .fixture(.appleBooks))
    #expect(row.title == "Los ritos del agua")
    #expect(row.detail == "Eva García Sáenz · Apple Books ebook")
    #expect(row.identifiers == nil)

    var edition = FoundEdition.fixture()
    edition.publisher = "Planeta"
    let listed = EditionRow(id: 1, edition: edition)
    #expect(listed.detail == "Eva García Sáenz · 2017 · Spanish")
    #expect(listed.identifiers == "Planeta · ISBN 9788408172277")

    let bare = EditionRow(
      id: 2, edition: .fixture(author: nil, year: nil, isbn: nil, language: nil))
    #expect(bare.detail == "")
    #expect(bare.identifiers == nil)
  }

  @Test func noSourcesNoLookup() {
    let script = ScriptedLookup()
    #expect(!self.sheet(lookup: nil).canLookUp)
    #expect(self.sheet(lookup: script.lookup()).canLookUp)

    let sheet = sheet(lookup: script.lookup(sources: []))
    #expect(!sheet.canLookUp)
    sheet.lookUp()
    #expect(script.queries.isEmpty)
    #expect(sheet.progress == nil)
  }

  @Test func coverFromDataHasItsPixelSize() throws {
    let file = try CoverImageFile.make(from: try png(width: 30, height: 45)).get()
    #expect(file.pixelWidth == 30)
    #expect(file.pixelHeight == 45)
    #expect(!file.preview.isEmpty)

    #expect(throws: EditDetailsError.imageTooLarge) {
      try CoverImageFile.make(from: Data(count: 21_000_000)).get()
    }
    #expect(throws: EditDetailsError.unreadableImage) {
      try CoverImageFile.make(from: Data("not an image".utf8)).get()
    }
  }

  @Test func differingFieldsShowFoundValues() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    sheet.language = "en"
    #expect(sheet.found(.year) == nil)
    #expect(await lookUp(sheet, script, finding: openLibrary))

    #expect(sheet.found(.title) == .matches)
    #expect(sheet.found(.author) == .differs("Eva García Sáenz"))
    #expect(sheet.found(.year) == .differs("2017"))
    #expect(sheet.found(.isbn) == .matches)
    #expect(sheet.found(.language) == .differs("Spanish"))
    #expect(sheet.found(.sortTitle) == nil && sheet.found(.sortName) == nil)
    #expect(sheet.differences == 3)

    // A field the source has no value for shows nothing.
    #expect(await lookUp(sheet, script, finding: .fixture(year: nil)))
    #expect(sheet.found(.year) == nil)
  }

  @Test func useFillsAndUndoRestores() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    sheet.language = "en"
    #expect(await lookUp(sheet, script, finding: openLibrary))

    sheet.use(.year)
    #expect(sheet.year == "2017")
    #expect(sheet.isEdited(.year))
    #expect(sheet.found(.year) == .used(was: "2016"))
    sheet.use(.language)
    #expect(sheet.language == "es")
    #expect(sheet.found(.language) == .used(was: "English"))
    #expect(sheet.differences == 3)

    // A matching field has nothing to use.
    sheet.use(.title)
    #expect(sheet.found(.title) == .matches)

    sheet.undo(.year)
    #expect(sheet.year == "2016")
    #expect(!sheet.isEdited(.year))
    #expect(sheet.found(.year) == .differs("2017"))
    sheet.undo(.language)
    #expect(sheet.language == "en")
    #expect(sheet.found(.language) == .differs("Spanish"))

    // An emptied field showed what it goes back to.
    sheet.year = ""
    sheet.use(.year)
    #expect(sheet.found(.year) == .used(was: "—"))
    sheet.undo(.year)
    #expect(sheet.year == "")

    let untagged = Book.fixture(
      id: "untagged", title: "Los ritos del agua", author: "Eva Garcia Saenz", language: nil)
    let other = self.sheet(untagged, lookup: script.lookup())
    #expect(await lookUp(other, script, finding: openLibrary))
    other.use(.language)
    #expect(other.found(.language) == .used(was: "—"))
    other.undo(.language)
    #expect(other.language == nil)
  }

  @Test func typingAfterUseDropsTheUndo() async {
    let script = ScriptedLookup()
    let sheet = sheet(lookup: script.lookup())
    #expect(await lookUp(sheet, script, finding: openLibrary))
    sheet.use(.author)
    sheet.use(.year)

    sheet.author = "Someone"
    #expect(sheet.found(.author) == .differs("Eva García Sáenz"))
    sheet.undo(.author)
    #expect(sheet.author == "Someone")

    // Typing the found value back doesn't bring Undo back.
    sheet.author = "Eva García Sáenz"
    #expect(sheet.found(.author) == .matches)

    sheet.undo(.year)
    #expect(sheet.year == "2016")
    #expect(sheet.author == "Eva García Sáenz")
  }

  @Test func useAuthorShowsTheWriterBox() async {
    let script = ScriptedLookup()
    let others = [
      Book.fixture(id: "b", author: "Eva García Sáenz"),
      .fixture(id: "c", author: "Saenz, Eva Garcia"),
    ]
    let sheet = sheet(library: others, lookup: script.lookup())
    #expect(await lookUp(sheet, script, finding: openLibrary))
    #expect(!sheet.showsWriterCheckbox)

    sheet.use(.author)
    #expect(sheet.author == "Eva García Sáenz")
    #expect(sheet.isEdited(.author))
    #expect(sheet.showsWriterCheckbox)
    #expect(sheet.changesWriter)
    #expect(sheet.writerCheckboxTitle == "Also change the 2 other books by \"Eva Garcia Saenz\"")
  }

  @Test func useAllSkipsTheCover() async throws {
    let script = ScriptedLookup(images: [coverURL: try png(width: 40, height: 60)])
    let sheet = sheet(lookup: script.lookup())
    sheet.language = "en"
    sheet.lookUp()
    script.send(
      progress(isbn: [.openLibrary: .found([withCover]), .appleBooks: .notFound], finished: true))
    #expect(await eventually { sheet.foundCover != nil })

    sheet.useAll()
    #expect(sheet.found(.author) == .used(was: "Eva Garcia Saenz"))
    #expect(sheet.found(.year) == .used(was: "2016"))
    #expect(sheet.found(.language) == .used(was: "English"))
    #expect(sheet.found(.title) == .matches && sheet.found(.isbn) == .matches)
    #expect(!sheet.isCoverEdited)
    #expect(!sheet.isFoundCoverUsed)
    // What was used still counts, so the banner doesn't turn into "agrees with everything".
    #expect(sheet.differences == 3)
    #expect(sheet.banner == .found(.openLibrary, differences: 3))
    #expect(sheet.sourceMenu.first?.status == "3 differences")
  }

  @Test func pdfComparesOnlyTitleAndAuthor() async {
    let script = ScriptedLookup()
    let pdf = Book.fixture(
      id: "pdf", title: "Los ritos del agua", author: "Eva Garcia Saenz", language: "en",
      format: .pdf)
    let sheet = sheet(pdf, lookup: script.lookup())
    #expect(await lookUp(sheet, script, finding: withCover))

    #expect(sheet.found(.author) == .differs("Eva García Sáenz"))
    #expect(sheet.found(.year) == nil)
    #expect(sheet.found(.isbn) == nil)
    #expect(sheet.found(.language) == nil)
    sheet.useAll()
    #expect(sheet.found(.author) == .used(was: "Eva Garcia Saenz"))
    #expect(sheet.year == "2016" && sheet.language == "en")
    await settle()
    #expect(sheet.foundCover == nil)
    #expect(script.imageRequests.isEmpty)
  }

  @Test func foundCoverIsOfferedNotCounted() async throws {
    let image = try png(width: 40, height: 60)
    let script = ScriptedLookup(images: [coverURL: image])
    let sheet = sheet(lookup: script.lookup())
    #expect(!sheet.isFoundCoverUsed)
    #expect(await lookUp(sheet, script, finding: withCover))
    #expect(await eventually { sheet.foundCover != nil })

    let cover = try #require(sheet.foundCover)
    #expect(cover.url == coverURL)
    #expect(cover.sizeText == "40 × 60")
    #expect(cover.file.data == image)
    #expect(script.imageRequests == [coverURL])
    #expect(sheet.differences == 2)
    #expect(!sheet.isFoundCoverUsed)

    sheet.useFoundCover()
    #expect(sheet.isCoverEdited)
    #expect(sheet.isFoundCoverUsed)
    #expect(sheet.coverPreview == cover.file.preview)
    #expect(sheet.differences == 2)

    sheet.undoFoundCover()
    #expect(!sheet.isCoverEdited)
    #expect(!sheet.isFoundCoverUsed)
    #expect(sheet.coverPreview == nil)

    // Choosing another image after Use cover leaves nothing to undo.
    sheet.useFoundCover()
    sheet.setCover(Data("chosen".utf8))
    #expect(!sheet.isFoundCoverUsed)
    sheet.undoFoundCover()
    #expect(sheet.coverPreview == Data("chosen".utf8))

    // An image that isn't one offers no cover.
    let broken = try #require(URL(string: "https://covers.example/broken-L.jpg"))
    var unreadable = openLibrary
    unreadable.cover = broken
    let junk = ScriptedLookup(images: [broken: Data("not an image".utf8)])
    let other = self.sheet(lookup: junk.lookup())
    #expect(await lookUp(other, junk, finding: unreadable))
    #expect(await eventually { junk.imageRequests == [broken] })
    await settle()
    #expect(other.foundCover == nil)
  }

  @Test func noCoverRowWhenCoverCantChange() async throws {
    let script = ScriptedLookup(images: [coverURL: try png(width: 40, height: 60)])
    let inCloud = Book.fixture(
      id: "cloud", title: "Los ritos del agua", author: "Eva Garcia Saenz", language: "es",
      availability: .inCloudOnly)
    let sheet = sheet(inCloud, lookup: script.lookup())
    #expect(await lookUp(sheet, script, finding: withCover))
    await settle()

    #expect(sheet.foundCover == nil)
    #expect(script.imageRequests.isEmpty)
    sheet.useFoundCover()
    #expect(!sheet.isCoverEdited)
  }

  @Test func aCoverNoLongerShownIsDropped() async throws {
    let appleCover = try #require(URL(string: "https://covers.example/apple-L.jpg"))
    let openLibraryGate = Signal()
    let appleGate = Signal()
    let script = ScriptedLookup(
      images: [
        coverURL: try png(width: 40, height: 60), appleCover: try png(width: 50, height: 75),
      ],
      imageGates: [coverURL: openLibraryGate, appleCover: appleGate])
    let sheet = sheet(lookup: script.lookup())
    var apple = self.apple
    apple.cover = appleCover
    sheet.lookUp()
    script.send(progress(isbn: [.openLibrary: .found([withCover]), .appleBooks: .found([apple])]))
    #expect(await eventually { script.imageRequests == [coverURL] })

    // Open Library's cover arrives once Apple Books is shown.
    sheet.show(.appleBooks)
    #expect(await eventually { script.imageRequests == [coverURL, appleCover] })
    await openLibraryGate.fire()
    await settle()
    #expect(sheet.foundCover == nil)

    // Apple Books' arrives once the lookup has ended.
    sheet.cancelLookup()
    await appleGate.fire()
    await settle()
    #expect(sheet.foundCover == nil)
  }

  @Test func endingTheLookupKeepsWhatWasUsed() async throws {
    let script = ScriptedLookup(images: [coverURL: try png(width: 40, height: 60)])
    let sheet = sheet(lookup: script.lookup())
    #expect(await lookUp(sheet, script, finding: openLibrary))
    sheet.use(.year)

    // A new lookup finds the used value as the field's own.
    #expect(await lookUp(sheet, script, finding: withCover))
    #expect(sheet.year == "2017")
    #expect(sheet.found(.year) == .matches)
    #expect(await eventually { sheet.foundCover != nil })
    sheet.use(.author)
    sheet.useFoundCover()

    sheet.cancelLookup()
    #expect(sheet.author == "Eva García Sáenz" && sheet.isCoverEdited)
    #expect(sheet.found(.author) == nil)
    #expect(sheet.foundCover == nil && !sheet.isFoundCoverUsed)
    sheet.undo(.author)
    sheet.undoFoundCover()
    #expect(sheet.author == "Eva García Sáenz" && sheet.isCoverEdited)
  }

  @Test func savingAfterUseSavesTheFoundValues() async throws {
    let image = try png(width: 40, height: 60)
    let script = ScriptedLookup(images: [coverURL: image])
    let saved = Recorder<BookDetailsDraft>()
    let sheet = sheet(saved: saved, lookup: script.lookup())
    #expect(await lookUp(sheet, script, finding: withCover))
    #expect(await eventually { sheet.foundCover != nil })
    sheet.use(.year)
    sheet.useFoundCover()

    #expect(await sheet.save())
    let draft = try #require(await saved.values.last)
    #expect(draft.year == "2017")
    #expect(draft.author == "Eva Garcia Saenz")
    #expect(draft.cover == .replace(image))
  }

  private func png(width: Int, height: Int) throws -> Data {
    struct Failure: Error {}
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
      let data = bitmap.representation(using: .png, properties: [:])
    else { throw Failure() }
    return data
  }
}
