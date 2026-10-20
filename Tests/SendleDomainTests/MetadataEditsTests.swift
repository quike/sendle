import Foundation
import SendleDomain
import Testing

@Suite(.timeLimit(.minutes(1)))
struct MetadataEditsTests {
  @Test func writerKeysIgnoreOrderCaseAccentsAndPunctuation() {
    let keys = ["Doe, John", "John Doe", "JOHN DOE", "Jöhn Doe."].map { WriterKey(author: $0) }
    #expect(Set(keys).count == 1)
    #expect(WriterKey(author: "Ann Smith & Bob Jones") == WriterKey(author: "Bob Jones; Ann Smith"))
    #expect(WriterKey(author: "  ") == nil)
    #expect(WriterKey(author: nil) == nil)
  }

  @Test func editsRoundTripAsJSONObjectsKeyedByID() throws {
    var edits = MetadataEdits.none
    edits.books[BookID(rawValue: "A1")] = BookEdit(title: "Patria")
    edits.writers[WriterKey(author: "Eva Garcia Saenz")!] = WriterEdit(
      sortName: "García Sáenz, Eva")
    let data = try JSONEncoder().encode(edits)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((json["books"] as? [String: Any])?["A1"] != nil)
    #expect(try JSONDecoder().decode(MetadataEdits.self, from: data) == edits)
  }

  @Test func writerKeysEncodeAsPlainStrings() throws {
    let key = try #require(WriterKey(author: "Eva García Sáenz"))
    let edits = MetadataEdits(writers: [key: WriterEdit(name: "Eva G. Sáenz")])
    let data = try JSONEncoder().encode(edits)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((json["writers"] as? [String: Any])?[key.rawValue] != nil)
  }

  @Test func aBookEditHasEditsUnlessOnlyItsChangeDateIsSet() {
    #expect(!BookEdit().hasEdits)
    #expect(!BookEdit(changedAt: Date(timeIntervalSince1970: 1)).hasEdits)
    #expect(BookEdit(cover: "A1.jpg").hasEdits)
    #expect(BookEdit(language: "es", changedAt: Date(timeIntervalSince1970: 1)).hasEdits)
  }

  @Test func aWriterEditIsEmptyWhenNeitherNameIsSet() {
    #expect(WriterEdit().isEmpty)
    #expect(WriterEdit(nameChangedAt: Date(timeIntervalSince1970: 1)).isEmpty)
    #expect(!WriterEdit(name: "Eva García Sáenz").isEmpty)
    #expect(!WriterEdit(sortName: "García Sáenz, Eva").isEmpty)
  }

  @Test func noEditsIsEmpty() {
    #expect(MetadataEdits.none.books.isEmpty)
    #expect(MetadataEdits.none.writers.isEmpty)
  }
}
