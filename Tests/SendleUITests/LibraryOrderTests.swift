import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

struct LibraryOrderTests {
  func titles(_ books: [Book]) -> [String] {
    books.map(\.title)
  }

  @Test func recentlyAddedKeepsTheLibrarysOrder() {
    let books = [Book.fixture(id: "b", title: "Zorba"), .fixture(id: "a", title: "Alice")]

    #expect(LibraryOrder.sorted(books, by: .recent) == books)
    #expect(LibraryOrder.letter(for: books[0], by: .recent) == nil)
  }

  @Test func titlesSortByBooksKeyIgnoringCaseAndAccents() {
    let books = [
      Book.fixture(id: "1", title: "Zorba the Greek"),
      .fixture(id: "2", title: "The Hobbit", sortTitle: "Hobbit, The"),
      .fixture(id: "3", title: "émile"),
      .fixture(id: "4", title: "alice in Wonderland"),
      .fixture(id: "5", title: "Ñandú"),
    ]

    let sorted = LibraryOrder.sorted(books, by: .title)

    #expect(
      titles(sorted) == ["alice in Wonderland", "émile", "The Hobbit", "Ñandú", "Zorba the Greek"])
    #expect(sorted.map { LibraryOrder.letter(for: $0, by: .title) } == ["A", "E", "H", "N", "Z"])
  }

  @Test func leadingPunctuationIsSkipped() {
    let books = [
      Book.fixture(id: "1", title: "'Salem's Lot"), .fixture(id: "2", title: "¡Ay, Carmela!"),
    ]

    let sorted = LibraryOrder.sorted(books, by: .title)

    #expect(titles(sorted) == ["¡Ay, Carmela!", "'Salem's Lot"])
    #expect(sorted.map { LibraryOrder.letter(for: $0, by: .title) } == ["A", "S"])
  }

  @Test func numbersAndOtherScriptsGoUnderHashAfterZ() {
    let books = [
      Book.fixture(id: "1", title: "Война и мир"), .fixture(id: "2", title: "1984"),
      .fixture(id: "3", title: "Zorba the Greek"),
    ]

    let sorted = LibraryOrder.sorted(books, by: .title)

    #expect(titles(sorted) == ["Zorba the Greek", "1984", "Война и мир"])
    #expect(sorted.map { LibraryOrder.letter(for: $0, by: .title) } == ["Z", "#", "#"])
  }

  @Test func authorsSortBySurnameKeyWithUnknownAuthorsLast() {
    let books = [
      Book.fixture(id: "1", title: "Untitled", author: nil),
      .fixture(id: "2", title: "Frankenstein", author: "Mary Shelley"),
      .fixture(id: "3", title: "Persuasion", author: "Jane Austen", sortAuthor: "Austen, Jane"),
      .fixture(id: "4", title: "Emma", author: "Jane Austen", sortAuthor: "Austen, Jane"),
      .fixture(id: "5", title: "1Q84", author: "1Q"),
    ]

    let sorted = LibraryOrder.sorted(books, by: .author)

    #expect(titles(sorted) == ["Emma", "Persuasion", "Frankenstein", "1Q84", "Untitled"])
    #expect(
      sorted.map { LibraryOrder.letter(for: $0, by: .author) } == ["A", "A", "M", "#", "#"])
  }

  @Test func equalKeysKeepAStableOrder() {
    let books = [Book.fixture(id: "b", title: "Emma"), .fixture(id: "a", title: "Emma")]

    #expect(LibraryOrder.sorted(books, by: .title).map(\.id.rawValue) == ["a", "b"])
  }
}

struct AlphabetIndexTests {
  let books = [
    Book.fixture(id: "a1", title: "Alice"), .fixture(id: "a2", title: "Anna Karenina"),
    .fixture(id: "c1", title: "Candide"), .fixture(id: "m1", title: "Middlemarch"),
  ]

  @Test func findsTheFirstBookUnderEachLetter() {
    let index = AlphabetIndex(books: books, sort: .title)

    #expect(index.lettersWithBooks == ["A", "C", "M"])
    #expect(index.target(for: "A") == BookID(rawValue: "a1"))
    #expect(index.target(for: "M") == BookID(rawValue: "m1"))
    #expect(index.letter(of: BookID(rawValue: "a2")) == "A")
  }

  @Test func aLetterWithoutBooksGoesToTheNextOneThatHasThem() {
    let index = AlphabetIndex(books: books, sort: .title)

    #expect(index.target(for: "B") == BookID(rawValue: "c1"))
    #expect(index.target(for: "D") == BookID(rawValue: "m1"))
  }

  @Test func pastTheLastLetterItGoesBackToTheLastBooks() {
    let index = AlphabetIndex(books: books, sort: .title)

    #expect(index.target(for: "Z") == BookID(rawValue: "m1"))
    #expect(index.target(for: "#") == BookID(rawValue: "m1"))
  }

  @Test func headersComeBeforeTheFirstBookOfEachLetter() {
    let index = AlphabetIndex(books: books, sort: .title)

    #expect(books.map { index.header(before: $0.id) } == ["A", nil, "C", "M"])
  }

  @Test func theRailListsEveryLetterThenHash() {
    #expect(LibraryOrder.letters.count == 27)
    #expect(LibraryOrder.letters.first == "A")
    #expect(LibraryOrder.letters.last == "#")
  }

  @Test func anEmptyOrUnsortedLibraryHasNoLetters() {
    #expect(AlphabetIndex(books: [], sort: .title).lettersWithBooks.isEmpty)
    #expect(AlphabetIndex(books: books, sort: .recent).lettersWithBooks.isEmpty)
    #expect(AlphabetIndex(books: [], sort: .title).target(for: "A") == nil)
  }
}
