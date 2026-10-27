import SendleDomain
import Testing

private let shown = ShownDetails(
  title: "Los ritos del agua", author: "Eva Garcia Saenz", year: "2016",
  isbn: "978-84-08-17227-9", language: "es")

@Suite(.timeLimit(.minutes(1)))
struct LookupDifferencesTests {
  @Test func accentsAndOrderAreDifferences() {
    let found = FoundEdition(
      source: .openLibrary, title: "Los ritos del agua", author: "Eva García Sáenz")
    let result = LookupDifferences.compare(found, with: shown)
    #expect(result[.title] == .matches)
    #expect(result[.author] == .differs("Eva García Sáenz"))
    #expect(result[.year] == nil)
  }

  @Test func isbnTenMatchesItsThirteen() {
    let shown = ShownDetails(
      title: "Dune", author: "", year: "", isbn: "9780441172719", language: nil)
    let found = FoundEdition(source: .googleBooks, isbn: "0-441-17271-7")
    #expect(LookupDifferences.compare(found, with: shown)[.isbn] == .matches)
  }

  @Test func yearMustBeFourDigits() {
    #expect(
      LookupDifferences.compare(FoundEdition(source: .openLibrary, year: "c1990"), with: shown)[
        .year] == nil)
    #expect(
      LookupDifferences.compare(FoundEdition(source: .openLibrary, year: "2017"), with: shown)[
        .year] == .differs("2017"))
  }

  @Test func languageComparesPrimarySubtags() {
    #expect(
      LookupDifferences.compare(FoundEdition(source: .googleBooks, language: "ES"), with: shown)[
        .language] == .matches)
    var none = shown
    none.language = nil
    #expect(
      LookupDifferences.compare(FoundEdition(source: .googleBooks, language: "es"), with: none)[
        .language] == .differs("es"))
  }

  @Test func blankFoundValuesAreAbsentAndTextIsTrimmed() {
    let found = FoundEdition(
      source: .openLibrary, title: "  Los ritos del agua \n", author: "   ", isbn: "123",
      language: " ")
    let result = LookupDifferences.compare(found, with: shown)
    #expect(result[.title] == .matches)
    #expect(result[.author] == nil)
    #expect(result[.isbn] == nil)
    #expect(result[.language] == nil)
  }

  @Test func aDifferentISBNCarriesTheThirteenDigits() {
    let found = FoundEdition(source: .openLibrary, isbn: "0-441-17271-7")
    #expect(LookupDifferences.compare(found, with: shown)[.isbn] == .differs("9780441172719"))
  }

  @Test func languageIgnoresRegionAndSeparator() {
    var other = shown
    other.language = "es_MX"
    let found = FoundEdition(source: .googleBooks, language: "es-ES")
    #expect(LookupDifferences.compare(found, with: other)[.language] == .matches)
    other.language = ""
    #expect(LookupDifferences.compare(found, with: other)[.language] == .differs("es-ES"))
  }
}
