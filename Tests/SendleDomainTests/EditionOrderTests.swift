import SendleDomain
import Testing

@Suite(.timeLimit(.minutes(1)))
struct EditionOrderTests {
  @Test func editionsInTheBooksLanguageWithISBNNewestFirst() {
    let a = FoundEdition(source: .openLibrary, year: "2021", isbn: "9780593311145", language: "en")
    let b = FoundEdition(source: .openLibrary, year: "2017", language: "es")
    let c = FoundEdition(source: .openLibrary, year: "2019", isbn: "9788408203119", language: "es")
    let d = FoundEdition(source: .openLibrary, year: "2017", isbn: "9788408172279", language: "es")
    #expect(EditionOrder.ranked([a, b, c, d], language: "es") == [c, d, b, a])
  }

  @Test func repeatedISBNsAndTheEleventhAreDropped() {
    let same = FoundEdition(source: .openLibrary, isbn: "9788408172279")
    let many = (0..<12).map { FoundEdition(source: .appleBooks, title: "\($0)") }
    #expect(EditionOrder.ranked([same, same], language: nil) == [same])
    #expect(EditionOrder.ranked(many, language: nil).count == 10)
  }

  @Test func editionsWithoutAYearComeLastAndTiesKeepTheirOrder() {
    let noYear = FoundEdition(source: .openLibrary, title: "none")
    let first = FoundEdition(source: .openLibrary, title: "first", year: "2010")
    let second = FoundEdition(source: .openLibrary, title: "second", year: "2010")
    let newest = FoundEdition(source: .openLibrary, title: "newest", year: "2020")
    #expect(
      EditionOrder.ranked([noYear, first, second, newest], language: nil)
        == [newest, first, second, noYear])
  }

  @Test func theBooksLanguageIgnoresRegionAndCase() {
    let other = FoundEdition(source: .openLibrary, title: "other", year: "2020", language: "en")
    let same = FoundEdition(source: .openLibrary, title: "same", year: "2000", language: "PT-br")
    #expect(EditionOrder.ranked([other, same], language: "pt_BR") == [same, other])
  }
}
