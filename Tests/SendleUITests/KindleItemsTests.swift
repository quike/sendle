import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor @Suite(.timeLimit(.minutes(1)))
struct KindleItemsTests {
  let books: [KindleBook] = [
    .fixture(
      path: "Dracula - Bram Stoker.azw3", title: "Dracula", authors: ["Bram Stoker"],
      source: .sendle, asin: "SN2Q7KXA4B", modified: Date(timeIntervalSince1970: 1_760_270_400)),
    .fixture(
      path: "Abreu, Andrea/Panza de burro - Andrea Abreu.azw3", title: "Panza de burro",
      authors: ["Andrea Abreu"], source: .calibre, byteCount: 1_200_000,
      modified: Date(timeIntervalSince1970: 1_760_000_000)),
    .fixture(
      path: "Downloads/Items01/The Hobbit_B007978NPG.kfx", title: "The Hobbit", authors: [],
      source: .amazon, modified: Date(timeIntervalSince1970: 1_750_000_000)),
    .fixture(
      path: "notes.txt", title: "notes", authors: [],
      modified: Date(timeIntervalSince1970: 1_740_000_000)),
  ]

  func makeModel(matching library: [Book] = []) async -> KindleViewModel {
    let model = makeKindleModel(reading: FakeKindleLibrary(.success(.fixture(books))))
    await model.follow(.fixture(), books: library)
    return model
  }

  @Test func searchesThisKindleByTitleOrAuthor() async {
    let model = await makeModel()
    model.query = "stoker"
    #expect(model.items.map(\.title) == ["Dracula"])
    model.query = "hobbit"
    #expect(model.items.map(\.title) == ["The Hobbit"])
  }

  @Test func everyWordMustMatch() async {
    let model = await makeModel()
    model.query = "abreu burro"
    #expect(model.items.map(\.title) == ["Panza de burro"])
    model.query = "abreu stoker"
    #expect(model.items.isEmpty)
  }

  @Test func fromSendleAndNotInLibrary() async {
    let model = await makeModel(matching: [
      .fixture(id: "d", title: "Dracula", author: "Bram Stoker")
    ])
    model.scope = .fromSendle
    #expect(model.items.map(\.title) == ["Dracula"])
    model.scope = .notInLibrary
    #expect(model.items.map(\.title) == ["Panza de burro", "The Hobbit", "notes"])
  }

  @Test func marksWhatTheLibraryHas() async {
    let model = await makeModel(matching: [
      .fixture(id: "d", title: "Dracula", author: "Bram Stoker")
    ])
    #expect(model.items.map(\.inLibrary) == [.maybe, nil, nil, nil])
  }

  @Test func listsOnlyTheFormatsPresent() async {
    let model = await makeModel()
    #expect(model.formats == ["azw3", "kfx", "txt"])
    model.format = "kfx"
    #expect(model.items.map(\.title) == ["The Hobbit"])
  }

  @Test func sortsByTitleAuthorOrNewestFile() async {
    let model = await makeModel()
    #expect(model.items.map(\.title) == ["Dracula", "Panza de burro", "The Hobbit", "notes"])
    model.sort = .title
    #expect(model.items.map(\.title) == ["Dracula", "notes", "Panza de burro", "The Hobbit"])
    model.sort = .author
    #expect(model.items.map(\.title) == ["Panza de burro", "Dracula", "notes", "The Hobbit"])
  }

  @Test func theShelfShowsTheNewestEight() async {
    let many = (1...10).map {
      KindleBook.fixture(
        path: "book\($0).azw3", title: "Book \($0)",
        modified: Date(timeIntervalSince1970: 1_700_000_000 + Double($0)))
    }
    let model = makeKindleModel(reading: FakeKindleLibrary(.success(.fixture(many))))
    await model.follow(.fixture(), books: [])
    model.sort = .title
    #expect(model.recentItems.map(\.title) == (3...10).reversed().map { "Book \($0)" })
  }

  @Test func eachBookSaysWhereItCameFrom() async {
    let model = await makeModel()
    let panza = model.items[1]
    #expect(panza.byline == "Andrea Abreu")
    #expect(panza.badge == "AZW3")
    #expect(panza.detail == "1.2 MB · From calibre")
    #expect(
      panza.help
        == "Panza de burro · Andrea Abreu\nAZW3 · 1.2 MB · From calibre\n"
        + "documents/Abreu, Andrea/Panza de burro - Andrea Abreu.azw3\n"
        + "Copied \(Formatting.day(panza.book.modified))")
    #expect(model.items[2].byline == "Unknown author")
  }

  @Test func saysWhetherTheLibraryHasEachBook() async {
    let model = await makeModel(matching: [
      .fixture(id: "d", title: "Dracula", author: "Bram Stoker")
    ])
    #expect(model.items[0].spoken == "AZW3, 1 MB · From Sendle, maybe in your library")
    #expect(model.items[1].spoken == "AZW3, 1.2 MB · From calibre, not in your library")
  }

  @Test func eachSourceHasALabel() {
    #expect(
      KindleBookSource.allCases.map(\.label) == [
        "From Sendle", "From calibre", "From Amazon", "Sent by email", "Copied by hand",
      ])
  }

  @Test func scopesHaveTitles() {
    #expect(KindleScope.allCases.map(\.title) == ["All", "From Sendle", "Not in Library"])
  }

  @Test func aFormatThatLeavesWithTheBookIsForgotten() async {
    let kindle = FakeKindleLibrary(.success(.fixture(books)))
    let model = makeKindleModel(reading: kindle)
    await model.follow(.fixture(), books: [])
    model.format = "kfx"
    kindle.result = .success(.fixture([books[0]]))
    await model.refresh()
    #expect(model.format == nil)
    #expect(model.items.map(\.title) == ["Dracula"])
  }
}
