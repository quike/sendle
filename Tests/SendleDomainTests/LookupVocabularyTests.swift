import SendleDomain
import Testing

@Suite(.timeLimit(.minutes(1)))
struct LookupVocabularyTests {
  @Test func sourcesKeepTheirOrder() {
    #expect(LookupSource.allCases.sorted() == [.openLibrary, .googleBooks, .appleBooks])
    #expect(LookupSource.appleBooks.name == "Apple Books")
    #expect(LookupSource.allCases.filter(\.givesDates) == [.openLibrary, .googleBooks])
  }

  @Test func queryNormalisesTheISBN() {
    let query = LookupQuery(
      title: " Dune ", author: "", isbn: "ISBN 0-441-17271-7", language: "pt_BR")
    #expect(query.title == "Dune")
    #expect(query.author == nil)
    #expect(query.isbn == "9780441172719")
    #expect(query.language == "pt")
    #expect(LookupQuery(title: "Dune", author: nil, isbn: "123", language: nil).isbn == nil)
  }

  @Test func lookupLogTag() {
    #expect(LogArea.lookup.tag == "LOOKUP")
  }
}
