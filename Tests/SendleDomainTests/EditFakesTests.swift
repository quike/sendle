import Foundation
import SendleDomain
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct EditFakesTests {
  let id = BookID(rawValue: "A1")

  @Test func aReplacedCoverIsNamedByItsDataLikeTheRealStore() async throws {
    let store = InMemoryMetadataEditStore()

    try await store.update(book: id, cover: .replace(Data("one".utf8))) { _ in }
    let first = try #require(await store.edits().books[id]?.cover)
    try await store.update(book: id, cover: .replace(Data("two".utf8))) { _ in }
    let second = try #require(await store.edits().books[id]?.cover)
    try await store.update(book: id, cover: .replace(Data("two".utf8))) { _ in }

    #expect(first.wholeMatch(of: /A1-[0-9a-f]{12}\.jpg/) != nil)
    #expect(second != first)
    #expect(await store.edits().books[id]?.cover == second)
    #expect(await store.covers == [id: Data("two".utf8)])
  }

  @Test func theChangeRunsBeforeTheCoverIsRecordedOnTheBook() async throws {
    let store = InMemoryMetadataEditStore()

    try await store.update(book: id, cover: .replace(Data("one".utf8))) {
      $0.books[id]?.title = "Ignored: no entry yet"
      $0.books[id, default: BookEdit()].year = "2016"
    }

    let edit = try #require(await store.edits().books[id])
    #expect(edit.title == nil)
    #expect(edit.year == "2016")
    #expect(edit.cover != nil)
  }

  @Test func revertingDropsTheCoverButKeepsTheOtherEdits() async throws {
    let store = InMemoryMetadataEditStore()
    try await store.update(book: id, cover: .replace(Data("one".utf8))) {
      $0.books[id] = BookEdit(title: "Patria")
    }

    try await store.update(book: id, cover: .revert) { _ in }

    #expect(await store.edits().books[id] == BookEdit(title: "Patria"))
    #expect(await store.covers.isEmpty)
  }

  @Test func aFailingStoreChangesNothing() async {
    let store = InMemoryMetadataEditStore(failure: .unreadableImage)

    await #expect(throws: MetadataEditError.unreadableImage) {
      try await store.update(book: id, cover: .replace(Data("one".utf8))) {
        $0.books[id] = BookEdit(title: "Patria")
      }
    }

    #expect(await store.edits() == .none)
    #expect(await store.covers.isEmpty)
  }
}
