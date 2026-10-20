import Foundation
import SendleDomain
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct PackageDetailsTests {
  private let cortazar = Book.fixture(
    title: "Rayuela", author: "Julio Cortázar", language: "es", sortAuthor: "Cortázar, Julio",
    edits: AppliedEdits(fields: [.author]))

  @Test func editedAuthorUnderSurnameWritesTheSortForm() {
    #expect(PackageDetails.for(cortazar, authorSort: .surname).creator == "Cortázar, Julio")
  }

  @Test func editedAuthorUnderFirstNameWritesTheShownAuthor() {
    #expect(PackageDetails.for(cortazar, authorSort: .firstName).creator == "Julio Cortázar")
  }

  @Test func editedMultiWriterAuthorWritesTheShownAuthor() {
    let book = Book.fixture(
      author: "Ann Smith & Bob Jones", sortAuthor: "Smith, Ann & Jones, Bob",
      edits: AppliedEdits(fields: [.writerName]))
    #expect(PackageDetails.for(book, authorSort: .surname).creator == "Ann Smith & Bob Jones")
  }

  @Test func editedAuthorWithoutAValidSortFormWritesTheShownAuthor() {
    let book = Book.fixture(
      author: "Plato", sortAuthor: "Plato", edits: AppliedEdits(fields: [.author]))
    #expect(PackageDetails.for(book, authorSort: .surname).creator == "Plato")
  }

  @Test func uneditedSingleWriterUnderSurnameWritesBooksSortForm() {
    let book = Book.fixture(author: "Herman Melville", sortAuthor: "Melville, Herman")
    let details = PackageDetails.for(book, authorSort: .surname)
    #expect(details.creator == "Melville, Herman")
    #expect(!details.isEmpty)
  }

  @Test func uneditedAuthorWithoutAValidSortFormIsLeftAlone() {
    for sortAuthor in [nil, "Melville Herman", "Melville, Herman, Jr.", "Melville, "] {
      let book = Book.fixture(author: "Herman Melville", sortAuthor: sortAuthor)
      #expect(PackageDetails.for(book, authorSort: .surname).creator == nil)
    }
    let multi = Book.fixture(author: "Ann Smith; Bob Jones", sortAuthor: "Smith, Ann")
    #expect(PackageDetails.for(multi, authorSort: .surname).creator == nil)
  }

  @Test func editedFieldsAreWrittenAsShown() {
    let cover = URL(filePath: "/Edits/edit-covers/book-1-0123456789ab.jpg")
    let book = Book.fixture(
      title: "Moby Dick; or, The Whale", language: "en-GB",
      edits: AppliedEdits(fields: [.title, .language, .year, .cover], year: "1851", cover: cover))
    let details = PackageDetails.for(book, authorSort: .firstName)
    #expect(details.title == "Moby Dick; or, The Whale")
    #expect(details.language == "en-GB")
    #expect(details.year == "1851")
    #expect(details.cover == cover)
    #expect(details.creator == nil)
    #expect(details.isbn == nil)
    #expect(!details.skipsISBN)
  }

  @Test func aSortTitleEditIsNeverWritten() {
    let book = Book.fixture(sortTitle: "Whale, The", edits: AppliedEdits(fields: [.sortTitle]))
    #expect(PackageDetails.for(book, authorSort: .firstName).isEmpty)
  }

  @Test func invalidISBNIsSkipped() {
    let book = Book.fixture(edits: AppliedEdits(fields: [.isbn], isbn: "123"))
    let details = PackageDetails.for(book, authorSort: .firstName)
    #expect(details.isbn == nil)
    #expect(details.skipsISBN)
    #expect(details.isEmpty)
  }

  @Test func validISBNIsWrittenAsThirteenDigits() {
    let book = Book.fixture(edits: AppliedEdits(fields: [.isbn], isbn: "0-306-40615-2"))
    let details = PackageDetails.for(book, authorSort: .firstName)
    #expect(details.isbn == "9780306406157")
    #expect(!details.skipsISBN)
  }

  @Test func nothingEditedUnderFirstNameIsEmpty() {
    let book = Book.fixture(author: "Herman Melville", sortAuthor: "Melville, Herman")
    let details = PackageDetails.for(book, authorSort: .firstName)
    #expect(details.isEmpty)
    #expect(details == PackageDetails())
  }
}
