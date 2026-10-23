import Foundation
import SendleDomain
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct KindleCopyPlannerTests {
  let planner = KindleCopyPlanner(asins: FakeASINScheme())
  let moby = Book.fixture(id: "moby")
  let edition = Edition(key: "urn:uuid:moby-dick")

  /// A file on the Kindle carrying the ASIN copy `copy` of Moby-Dick's edition gets.
  func onKindle(copy: Int) -> KindleBook {
    .fixture(
      path: "Copy \(copy).azw3", title: "Copy \(copy)", source: .sendle,
      asin: FakeASINScheme().asin(
        forSeed: FileNaming.asinSeed(for: moby, edition: edition, copy: copy)))
  }

  @Test func aFreeEditionASINIsLeftAsItIs() {
    let copies: [BookID: KindleCopy] = [moby.id: .keepBoth(2)]

    #expect(
      planner.plan(
        [moby], copies: copies, editions: [moby.id: edition], listing: [onKindle(copy: 1)])
        == copies)
    #expect(planner.plan([moby], copies: [:], editions: [moby.id: edition], listing: []).isEmpty)
  }

  @Test func aTakenEditionASINMovesToTheNextFreeNumber() {
    let listing = [onKindle(copy: 1), onKindle(copy: 2)]

    #expect(
      planner.plan([moby], copies: [:], editions: [moby.id: edition], listing: listing)
        == [moby.id: KindleCopy(name: 1, asin: 3)])
    #expect(
      planner.plan(
        [moby], copies: [moby.id: .keepBoth(2)], editions: [moby.id: edition], listing: listing)
        == [moby.id: KindleCopy(name: 2, asin: 3)])
  }

  @Test func twoBooksInOneSendNeverShareAnASIN() {
    // A placeholder identifier can give unrelated EPUBs one edition key.
    let other = Book.fixture(id: "other", title: "Dracula", author: "Bram Stoker")

    let planned = planner.plan(
      [moby, other], copies: [:], editions: [moby.id: edition, other.id: edition], listing: [])

    #expect(planned == [other.id: KindleCopy(name: 1, asin: 2)])
  }

  @Test func replacementsAndKeylessBooksAreLeftAlone() {
    let dracula = Book.fixture(id: "dracula", title: "Dracula", author: "Bram Stoker")
    let byName = KindleBook.fixture(
      path: "Dracula - Bram Stoker.azw3", title: "Other", source: .sendle,
      asin: FakeASINScheme().asin(forSeed: "Dracula - Bram Stoker"))
    let copies: [BookID: KindleCopy] = [
      moby.id: .replacing(asin: onKindle(copy: 1).asin ?? "")
    ]

    let planned = planner.plan(
      [moby, dracula], copies: copies,
      editions: [moby.id: edition, dracula.id: Edition(key: "  ")],
      listing: [onKindle(copy: 1), byName])

    #expect(planned == copies)
  }

  @Test func aReplacementKeepsTheCopyItRemoves() {
    let old = KindleBook.fixture(path: "Melville, Herman/Moby-Dick - Herman Melville.pdf")

    let planned = planner.plan(
      [moby], copies: [moby.id: KindleCopy(name: 1, asin: 1, removes: old)],
      editions: [moby.id: edition], listing: [onKindle(copy: 1)])

    #expect(planned == [moby.id: KindleCopy(name: 1, asin: 2, removes: old)])
  }

  @Test func aCopyOverwritingAFileKeepsThatFilesASIN() {
    let own = KindleBook.fixture(
      path: "moby-dick - herman melville.AZW3", source: .sendle, asin: onKindle(copy: 1).asin)
    let nested = KindleBook.fixture(
      path: "Books/Moby-Dick - Herman Melville.azw3", source: .sendle, asin: onKindle(copy: 1).asin)

    #expect(planner.plan([moby], copies: [:], editions: [moby.id: edition], listing: [own]).isEmpty)
    #expect(
      planner.plan(
        [moby], copies: [:], editions: [moby.id: edition], listing: [own, onKindle(copy: 1)])
        == [moby.id: KindleCopy(name: 1, asin: 2)])
    #expect(
      planner.plan([moby], copies: [:], editions: [moby.id: edition], listing: [nested])
        == [moby.id: KindleCopy(name: 1, asin: 2)])
  }

  @Test func wrapsAroundToAFreeNumberBelowItsOwn() {
    let listing = ([1] + Array(3...FileNaming.editionCopyLimit)).map { onKindle(copy: $0) }

    #expect(
      planner.plan(
        [moby], copies: [moby.id: .keepBoth(3)], editions: [moby.id: edition], listing: listing)
        == [moby.id: KindleCopy(name: 3, asin: 2)])
    #expect(
      planner.plan(
        [moby], copies: [moby.id: .keepBoth(12)], editions: [moby.id: edition],
        listing: listing + [onKindle(copy: 12)])
        == [moby.id: KindleCopy(name: 12, asin: 2)])
  }

  @Test func givesUpAtTheEditionCopyLimit() {
    let listing = (1...FileNaming.editionCopyLimit).map { onKindle(copy: $0) }

    #expect(
      planner.plan([moby], copies: [:], editions: [moby.id: edition], listing: listing).isEmpty)
    #expect(
      planner.plan(
        [moby], copies: [moby.id: .keepBoth(5)], editions: [moby.id: edition], listing: listing)
        == [moby.id: .keepBoth(5)])
  }
}
