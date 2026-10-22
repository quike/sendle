import SendleDomain
import Testing

struct HiddenBooksStoreTests {
  @Test func theNoHiddenBooksStoreHidesNothingAndRefusesChanges() async {
    let store = NoHiddenBooks()

    #expect(await store.hidden().isEmpty)
    await #expect(throws: StorageError.writeFailed("No hidden books")) {
      try await store.set([BookID(rawValue: "A1")], hidden: true)
    }
    #expect(await store.hidden().isEmpty)
  }
}
