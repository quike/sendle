import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

struct LibraryItemsTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let moby = Book.fixture(id: "moby", title: "Moby-Dick", author: "Herman Melville")
  let jane = Book.fixture(id: "jane", title: "Jane Eyre", author: "Charlotte Brontë")
  let manual = Book.fixture(id: "manual", title: "Swift Manual", author: nil, format: .pdf)

  func items(
    _ books: [Book],
    sends: [SendRecord] = [],
    filter: LibraryFilter = .all,
    query: String = "",
    to destination: DestinationKind = .email
  ) -> [BookItemViewModel] {
    LibraryItems.make(
      books: books, sends: LibraryItems.latestSends(in: sends), filter: filter, query: query,
      destination: destination, converterAvailable: false, now: now)
  }

  func sent(_ book: Book, daysAgo: Double, _ outcome: SendOutcome = .sent) -> SendRecord {
    SendRecord(
      bookID: book.id, destination: .email, date: now.addingTimeInterval(-daysAgo * 86_400),
      outcome: outcome)
  }

  @Test func filtersByFormat() {
    #expect(items([moby, manual], filter: .epub).map(\.id) == [moby.id])
    #expect(items([moby, manual], filter: .pdf).map(\.id) == [manual.id])
    #expect(items([moby, manual], filter: .all).map(\.id) == [moby.id, manual.id])
  }

  @Test func notSentHidesBooksAlreadyDelivered() {
    let sends = [sent(moby, daysAgo: 2), sent(jane, daysAgo: 1, .failed)]

    #expect(items([moby, jane], sends: sends, filter: .notSent).map(\.id) == [jane.id])
  }

  @Test(arguments: ["melville", "MOBY", "bronte", "  eyre  "])
  func searchMatchesTitleOrAuthorIgnoringCaseAndAccents(query: String) {
    #expect(items([moby, jane], query: query).count == 1)
  }

  @Test func everyWordOfASearchMustMatch() {
    #expect(items([moby, jane], query: "moby melville").map(\.id) == [moby.id])
    #expect(items([moby, jane], query: "moby bronte").isEmpty)
    #expect(items([moby, jane], query: "   ").count == 2)
  }

  @Test func describesASendableBook() throws {
    let item = try #require(items([.fixture(sizeBytes: 1_400_000)]).first)

    #expect(item.title == "Moby-Dick")
    #expect(item.byline == "Herman Melville")
    #expect(item.badge == "EPUB")
    #expect(item.detail == "1.4 MB")
    #expect(item.tone == .plain)
    #expect(item.canSend)
  }

  @Test func namesAMissingAuthorAndAStorePurchase() throws {
    let item = try #require(items([.fixture(author: nil, isStorePurchase: true)]).first)

    #expect(item.byline == "Unknown author")
    #expect(item.badge == "STORE")
  }

  @Test func showsTheLastSuccessfulSend() throws {
    let sends = [sent(moby, daysAgo: 5), sent(moby, daysAgo: 2), sent(moby, daysAgo: 1, .failed)]

    let item = try #require(items([moby], sends: sends).first)

    #expect(item.detail == "Sent by email · 2d ago")
    #expect(item.tone == .sent)
    #expect(item.canSend)
  }

  @Test(arguments: [Availability.protected, .inCloudOnly, .missing])
  func explainsWhyABookCannotBeSent(availability: Availability) throws {
    let book = Book.fixture(availability: availability)
    let item = try #require(items([book]).first)

    let reason: SendFailure =
      switch availability {
      case .protected: .protected
      case .inCloudOnly: .inCloudOnly
      default: .missing
      }
    #expect(item.detail == ProblemPresenter.problem(for: reason).title)
    #expect(item.tone == .unavailable)
    #expect(!item.canSend)
  }

  @Test func warnsWhenAPDFIsTooLargeToEmailButNotToCopy() throws {
    let big = Book.fixture(format: .pdf, sizeBytes: 62_000_000)

    let email = try #require(items([big], to: .email).first)
    let usb = try #require(items([big], to: .usb).first)

    #expect(email.detail == "62 MB is over Amazon's 50 MB email limit")
    #expect(email.tone == .warning)
    #expect(!email.canSend)
    #expect(usb.canSend)
  }

  @Test func keepsATitleCardsColoursAcrossLaunches() {
    #expect(TitleCard.paletteIndex(for: BookID(rawValue: "book-1"), count: 6) == 2)
    #expect(TitleCard.paletteIndex(for: BookID(rawValue: "book-2"), count: 6) == 3)

    let used = Set(
      (0..<60).map { TitleCard.paletteIndex(for: BookID(rawValue: "id-\($0)"), count: 6) })
    #expect(used == Set(0..<6))
  }
}
