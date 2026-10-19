import Foundation
import SendleDomain
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct MatchKindleBooksTests {
  let editions = FakeEditionReader([BookID(rawValue: "moby"): Edition(isbn: "9780306406157")])
  let digests = FakeFileDigester()
  let history = InMemorySendHistoryStore()
  var match: MatchKindleBooks {
    MatchKindleBooks(
      editions: editions, digests: digests, asins: FakeASINScheme(), history: history)
  }

  @Test func readsNoEditionsWhenNoKindleBookCouldCarryAKey() async {
    _ = await match(
      [.fixture(id: "moby")],
      against: [
        .fixture(),
        .fixture(source: .sendle, asin: "SNFNYTPPHY", asinFollowsFileName: true),
      ],
      on: .fixture())
    #expect(editions.requests.isEmpty)
  }

  @Test func copiesOfAnEditionAreSureUpToTheNinth() async {
    let keyed = FakeEditionReader([BookID(rawValue: "moby"): Edition(key: "urn:uuid:moby-dick")])
    let match = MatchKindleBooks(
      editions: keyed, digests: digests, asins: FakeASINScheme(), history: history)
    let third = KindleBook.fixture(
      path: "x.azw3", title: "X", source: .sendle, asin: "SN:edition:urn:uuid:moby-dick#3")
    let thirdMatch = await match([.fixture(id: "moby")], against: [third], on: .fixture())
    #expect(thirdMatch.byBook[BookID(rawValue: "moby")]?.reason == .editionKey)
    let tenth = KindleBook.fixture(
      path: "x.azw3", title: "X", source: .sendle, asin: "SN:edition:urn:uuid:moby-dick#10")
    let tenthMatch = await match([.fixture(id: "moby")], against: [tenth], on: .fixture())
    #expect(tenthMatch.byBook.isEmpty)
  }

  @Test func asksOnlyForEPUBsOnThisMac() async {
    let books: [Book] = [
      .fixture(id: "moby"), .fixture(id: "cloud", availability: .inCloudOnly),
      .fixture(id: "pdf", format: .pdf), .fixture(id: "locked", availability: .protected),
    ]
    let found = await match(
      books, against: [.fixture(title: "X", isbn: "0306406152")], on: .fixture())
    #expect(editions.requests == [[BookID(rawValue: "moby"), BookID(rawValue: "locked")]])
    #expect(found.byBook[BookID(rawValue: "moby")]?.reason == .isbn)
  }

  @Test func hashesOnlyPDFsOfTheSameSize() async {
    let pdf = Book.fixture(
      id: "orwell", title: "1984", format: .pdf, fileURL: URL(filePath: "/Books/1984.pdf"),
      sizeBytes: 1_000)
    let same = KindleBook.fixture(path: "a.pdf", title: "a", byteCount: 1_000)
    let other = KindleBook.fixture(path: "b.pdf", title: "b", byteCount: 2_000)
    let kindle = KindleVolume.fixture()
    let digests = FakeFileDigester([pdf.fileURL: "d1", same.url(on: kindle): "d1"])
    let found = await MatchKindleBooks(
      editions: editions, digests: digests, asins: FakeASINScheme(), history: history)(
        [pdf], against: [same, other], on: kindle)
    #expect(Set(digests.requests) == [pdf.fileURL, same.url(on: kindle)])
    #expect(found.byBook[pdf.id]?.reason == .sameContent)
  }

  @Test func onlyAConfirmedEmailCountsAsEmailed() async throws {
    let bleak = Book.fixture(id: "bleak", title: "Bleak House", author: "Charles Dickens")
    let download = KindleBook.fixture(
      path: "Downloads/Items01/Bleak House_0123456789ABCDEF0123456789ABCDEF.kfx",
      title: "Bleak House", authors: [], source: .email)
    try await history.append(
      SendRecord(bookID: bleak.id, destination: .email, date: .now, outcome: .unconfirmed))
    let unconfirmed = await match([bleak], against: [download], on: .fixture())
    #expect(unconfirmed.byBook[bleak.id]?.confidence == .maybe)
    try await history.append(
      SendRecord(bookID: bleak.id, destination: .email, date: .now, outcome: .sent))
    let confirmed = await match([bleak], against: [download], on: .fixture())
    #expect(confirmed.byBook[bleak.id]?.confidence == .sure)
  }
}
