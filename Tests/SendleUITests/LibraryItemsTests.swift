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
    format: BookFormat? = nil,
    query: String = "",
    to destination: DestinationKind = .email,
    kindle: KindleMatches? = nil
  ) -> [BookItemViewModel] {
    LibraryItems.make(
      books: books, sends: LibraryItems.sendsByBook(in: sends), filter: filter, format: format,
      query: query, destination: destination, converterAvailable: false, kindle: kindle, now: now)
  }

  func item(_ book: Book, _ sends: [SendRecord], kindle: KindlePresence) -> BookItemViewModel {
    let matches: KindleMatches? =
      switch kindle {
      case .none: nil
      case .notOnKindle: .empty
      case .on(let confidence):
        KindleMatches(
          byBook: [
            book.id: KindleMatch(
              book: .fixture(), confidence: confidence,
              reason: confidence == .sure ? .sendleName : .titleAndAuthor)
          ], onKindle: [:])
      }
    return items([book], sends: sends, kindle: matches)[0]
  }

  func sent(
    _ book: Book, daysAgo: Double, _ outcome: SendOutcome = .sent, by kind: DestinationKind = .email
  ) -> SendRecord {
    SendRecord(
      bookID: book.id, destination: kind, date: now.addingTimeInterval(-daysAgo * 86_400),
      outcome: outcome)
  }

  @Test func filtersByFormat() {
    #expect(items([moby, manual], format: .epub).map(\.id) == [moby.id])
    #expect(items([moby, manual], format: .pdf).map(\.id) == [manual.id])
    #expect(items([moby, manual]).map(\.id) == [moby.id, manual.id])
    #expect(items([moby, manual], filter: .notSent, format: .pdf).map(\.id) == [manual.id])
  }

  @Test func onKindleIncludesSureAndMaybeAndNotOnKindleIsTheRest() {
    let kindle = KindleMatches(
      byBook: [
        moby.id: KindleMatch(book: .fixture(), confidence: .sure, reason: .sendleName),
        jane.id: KindleMatch(
          book: .fixture(title: "Jane Eyre"), confidence: .maybe, reason: .titleAndAuthor),
      ],
      onKindle: [:])

    #expect(
      items([moby, jane, manual], filter: .onKindle, kindle: kindle).map(\.id) == [
        moby.id, jane.id,
      ]
    )
    #expect(
      items([moby, jane, manual], filter: .notOnKindle, kindle: kindle).map(\.id) == [manual.id])
  }

  @Test func notSentHidesBooksAlreadyDelivered() {
    let sends = [sent(moby, daysAgo: 2), sent(jane, daysAgo: 1, .failed)]

    #expect(items([moby, jane], sends: sends, filter: .notSent).map(\.id) == [jane.id])
  }

  @Test func notSentHidesBooksThatMayHaveBeenSent() {
    let sends = [sent(moby, daysAgo: 1, .unconfirmed)]

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

  @Test func warnsThatAnUnconfirmedBookMayHaveBeenSent() throws {
    let sends = [sent(moby, daysAgo: 3), sent(moby, daysAgo: 1, .unconfirmed)]

    let item = try #require(items([moby], sends: sends).first)

    #expect(item.detail == "May have been sent · check your Kindle")
    #expect(item.tone == .warning)
    #expect(item.canSend)
  }

  @Test func aLaterSendSettlesAnUnconfirmedOne() throws {
    let sends = [sent(moby, daysAgo: 3, .unconfirmed), sent(moby, daysAgo: 2)]

    let item = try #require(items([moby], sends: sends).first)

    #expect(item.detail == "Sent by email · 2d ago")
    #expect(item.tone == .sent)
  }

  @Test func marksEveryWayABookWasSent() throws {
    let usbDate = now.addingTimeInterval(-86_400)
    let sends = [sent(moby, daysAgo: 3), sent(moby, daysAgo: 1, by: .usb)]

    let item = try #require(items([moby], sends: sends).first)

    #expect(item.routes == [.email, .usb])
    #expect(item.tone == .sent)
    #expect(item.detail == "Sent by email and over USB · \(Formatting.age(of: usbDate, now: now))")
  }

  @Test func oneRouteKeepsItsWording() throws {
    let item = try #require(items([moby], sends: [sent(moby, daysAgo: 2, by: .usb)]).first)

    #expect(item.routes == [.usb])
    #expect(item.detail.hasPrefix("Sent over USB · "))
  }

  @Test func failedSendsLeaveNoMark() throws {
    let item = try #require(items([moby], sends: [sent(moby, daysAgo: 1, .failed)]).first)

    #expect(item.routes.isEmpty)
    #expect(item.tone == .plain)
  }

  @Test func anUnconfirmedSendWarnsWithoutAMark() throws {
    let item = try #require(items([moby], sends: [sent(moby, daysAgo: 1, .unconfirmed)]).first)

    #expect(item.routes.isEmpty)
    #expect(item.tone == .warning)
    #expect(item.detail == "May have been sent · check your Kindle")
  }

  @Test func anUnconfirmedEmailKeepsAnEarlierUSBMark() throws {
    let sends = [sent(moby, daysAgo: 2, by: .usb), sent(moby, daysAgo: 1, .unconfirmed)]

    let item = try #require(items([moby], sends: sends).first)

    #expect(item.routes == [.usb])
    #expect(item.tone == .warning)
  }

  @Test func routesShowWhenTheBookCantGoToTheActiveDestination() throws {
    let cloud = Book.fixture(availability: .inCloudOnly)

    let item = try #require(items([cloud], sends: [sent(cloud, daysAgo: 2)]).first)

    #expect(item.routes == [.email])
    #expect(!item.canSend)
  }

  @Test func spokenRoutesCoverTheSendsTheDetailDoesNotName() throws {
    let cloud = Book.fixture(availability: .inCloudOnly)
    let both = [sent(moby, daysAgo: 3), sent(moby, daysAgo: 2, by: .usb)]
    let afterUSB = [sent(moby, daysAgo: 2, by: .usb), sent(moby, daysAgo: 1, .unconfirmed)]

    let blocked = try #require(items([cloud], sends: [sent(cloud, daysAgo: 2)]).first)
    let warned = try #require(items([moby], sends: afterUSB).first)
    let bothWays = try #require(
      items([moby], sends: both + [sent(moby, daysAgo: 1, .unconfirmed)]).first)

    #expect(blocked.spokenRoutes == "Sent by email before")
    #expect(warned.spokenRoutes == "Sent over USB before")
    #expect(bothWays.spokenRoutes == "Sent by email and over USB before")
  }

  @Test func spokenRoutesStayQuietWhenTheDetailSaysIt() throws {
    let sentItem = try #require(items([moby], sends: [sent(moby, daysAgo: 1)]).first)
    let neverSent = try #require(items([moby]).first)

    #expect(sentItem.spokenRoutes == nil)
    #expect(neverSent.spokenRoutes == nil)
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

  @Test func whatIsOnTheKindleOutranksTheHistory() {
    let sends = [sent(moby, daysAgo: 2, by: .email), sent(moby, daysAgo: 1, by: .usb)]

    #expect(
      item(moby, sends, kindle: .on(.sure)).marks == [.route(.email, dimmed: false), .onKindle])
    #expect(
      item(moby, sends, kindle: .on(.maybe)).marks == [
        .route(.email, dimmed: false), .maybeOnKindle,
      ])
    #expect(
      item(moby, sends, kindle: .notOnKindle).marks == [
        .route(.email, dimmed: false), .route(.usb, dimmed: true),
      ])
    #expect(
      item(moby, sends, kindle: .none).marks == [
        .route(.email, dimmed: false), .route(.usb, dimmed: false),
      ])
    #expect(item(moby, [], kindle: .on(.sure)).marks == [.onKindle])
  }

  @Test func theKindleStateIsSaidInWords() {
    #expect(item(moby, [], kindle: .on(.sure)).kindleText == "On this Kindle")
    #expect(
      item(moby, [], kindle: .on(.maybe)).kindleText == "Maybe on this Kindle · another edition?")
    #expect(
      item(moby, [sent(moby, daysAgo: 1, by: .usb)], kindle: .notOnKindle).kindleText
        == "Sent over USB · not on this Kindle")
    #expect(item(moby, [], kindle: .notOnKindle).kindleText == nil)
    #expect(item(moby, [], kindle: .none).kindleText == nil)
  }

  @Test func marksHaveTheirSymbols() {
    #expect(BookMark.onKindle.symbol == "ipad")
    #expect(BookMark.maybeOnKindle.symbol == "questionmark")
    #expect(BookMark.route(.usb, dimmed: true).symbol == DestinationKind.usb.symbol)
  }

  @Test func iCloudCoversAreDimmedLessAndMarked() {
    #expect(CoverLook.of(.ready) == CoverLook(saturation: 1, brightness: 0, showsCloud: false))
    #expect(
      CoverLook.of(.inCloudOnly) == CoverLook(saturation: 0.6, brightness: -0.1, showsCloud: true))
    #expect(
      CoverLook.of(.protected) == CoverLook(saturation: 0.2, brightness: -0.3, showsCloud: false))
    #expect(
      CoverLook.of(.missing) == CoverLook(saturation: 0.2, brightness: -0.3, showsCloud: false))
  }
}
