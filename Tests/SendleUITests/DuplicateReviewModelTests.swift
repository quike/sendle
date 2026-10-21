import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor
struct DuplicateReviewModelTests {
  func duplicate(
    _ id: String, _ confidence: MatchConfidence, _ replace: ReplaceKind = .inPlace,
    kindle: KindleBook = .fixture(), edition: Edition? = nil,
    reason: MatchReason? = nil
  ) -> DuplicateCase {
    DuplicateCase(
      book: .fixture(id: id), edition: edition,
      match: KindleMatch(
        book: kindle, confidence: confidence,
        reason: reason ?? (confidence == .sure ? .sendleName : .titleAndAuthor)),
      replace: replace)
  }

  @Test func opensOnTheFirstDuplicate() {
    let model = DuplicateReviewModel(cases: [
      duplicate("a", .sure), duplicate("b", .maybe), duplicate("c", .sure),
    ])
    #expect(model.counter == "1 of 3")
    #expect(model.badge == "Same edition")
    model.choose(.skip)
    #expect(model.counter == "2 of 3")
    #expect(model.badge == "Same title and author · maybe another edition")
  }

  @Test func aMatchOnTheTitleAloneDoesNotClaimTheAuthor() {
    let model = DuplicateReviewModel(cases: [duplicate("a", .maybe, reason: .titleOnly)])
    #expect(model.badge == "Same title · maybe another edition")
  }

  @Test func titlesTheChoices() {
    #expect(
      [DuplicateChoice.skip, .keepBoth, .replace].map(\.title) == ["Skip", "Keep both", "Replace"])
  }

  @Test func returnReplacesASureMatchAndSkipsAMaybe() {
    let model = DuplicateReviewModel(cases: [duplicate("a", .sure), duplicate("b", .maybe)])
    #expect(model.defaultChoice == .replace)
    model.chooseDefault()
    #expect(model.defaultChoice == .skip)
    model.chooseDefault()
    #expect(model.decisions == [BookID(rawValue: "a"): .replace, BookID(rawValue: "b"): .skip])
    #expect(model.isFinished)
  }

  @Test func offersAllThreeChoicesWhereReplaceIsPossible() {
    let model = DuplicateReviewModel(cases: [duplicate("a", .sure)])
    #expect(model.choices == [.skip, .keepBoth, .replace])
  }

  @Test func aCopySendleDidNotMakeCannotBeReplacedYet() {
    let model = DuplicateReviewModel(cases: [duplicate("a", .sure, .unavailable)])
    #expect(model.choices == [.skip, .keepBoth])
    #expect(model.defaultChoice == .skip)
    #expect(
      model.note
        == "Sendle didn't put this copy on the Kindle, so it won't replace it. Skip it, or keep both."
    )
  }

  @Test func aCopyOfSendlesWithAnotherNameSaysSo() {
    let model = DuplicateReviewModel(cases: [
      duplicate("a", .maybe, .unavailable, kindle: .fixture(source: .sendle))
    ])
    #expect(
      model.note
        == "This copy has another name on the Kindle, so Sendle won't replace it. Skip it, or keep both."
    )
  }

  @Test func refusesAChoiceItDoesNotOffer() {
    let model = DuplicateReviewModel(cases: [duplicate("a", .sure, .unavailable)])
    model.choose(.replace)
    #expect(model.decisions.isEmpty)
    #expect(!model.isFinished)
  }

  @Test func applyingToTheRestStaysWithinTheSameConfidence() {
    let model = DuplicateReviewModel(cases: [
      duplicate("a", .sure), duplicate("b", .maybe), duplicate("c", .sure), duplicate("d", .maybe),
    ])
    model.appliesToRest = true
    model.choose(.replace)
    #expect(model.current.id.rawValue == "b")
    #expect(model.decisions[BookID(rawValue: "c")] == .replace)
    #expect(model.decisions[BookID(rawValue: "d")] == nil)
    model.choose(.keepBoth)
    #expect(model.decisions[BookID(rawValue: "d")] == .keepBoth)
    #expect(model.isFinished)
  }

  @Test func appliesToTheRestOnlyWhereAnotherOfTheSameConfidenceIsLeft() {
    let model = DuplicateReviewModel(cases: [
      duplicate("a", .sure), duplicate("b", .maybe), duplicate("c", .sure),
    ])
    #expect(model.canApplyToRest)
    model.choose(.skip)
    #expect(!model.canApplyToRest)
    model.choose(.skip)
    #expect(!model.canApplyToRest)
    model.choose(.skip)
    #expect(model.isFinished)
    #expect(!model.canApplyToRest)
  }

  @Test func aReplaceIsNotAppliedToACopyItCannotReplace() {
    let model = DuplicateReviewModel(cases: [
      duplicate("a", .sure), duplicate("b", .sure, .unavailable),
    ])
    model.appliesToRest = true
    model.choose(.replace)
    #expect(!model.isFinished)
    #expect(model.current.id.rawValue == "b")
  }

  @Test func differingValuesAreMarked() {
    let kindle = KindleBook.fixture(
      title: "Moby Dick", isbn: "9780141439518", publisher: "Penguin", byteCount: 900_000)
    let model = DuplicateReviewModel(
      cases: [
        duplicate(
          "a", .maybe, kindle: kindle,
          edition: Edition(isbn: "9780306406157", publisher: "penguin"))
      ], zone: .gmt)

    let rows = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.label, $0) })

    #expect(model.rows.map(\.label).prefix(4) == ["Title", "Author", "Publisher", "ISBN"])
    #expect(rows["Title"]?.differs == false)
    #expect(rows["ISBN"]?.differs == true)
    #expect(rows["Publisher"]?.differs == false)
    #expect(
      rows["Format"]
        == ComparisonRow(label: "Format", library: "EPUB → AZW3", kindle: "AZW3", differs: false))
    #expect(
      rows["Date"]
        == ComparisonRow(
          label: "Date", library: "Added 14 Nov 2023", kindle: "Copied 12 Oct 2025",
          differs: false))
    #expect(rows["Source"]?.kindle == "Copied by hand")
    #expect(rows["Source"]?.library == "Books library")
    #expect(rows["Size"]?.differs == false)
  }

  @Test func aKindleAuthorInSortFormReadsAsAName() {
    let kindle = KindleBook.fixture(authors: ["Melville, Herman", "Ann Smith & Bob Jones"])
    let model = DuplicateReviewModel(cases: [duplicate("a", .maybe, kindle: kindle)], zone: .gmt)

    let author = model.rows.first { $0.label == "Author" }
    #expect(author?.kindle == "Herman Melville, Ann Smith & Bob Jones")
    #expect(author?.differs == false)
  }

  @Test func showsADashWhereAValueIsMissing() {
    let kindle = KindleBook.fixture(authors: [])
    let model = DuplicateReviewModel(
      cases: [duplicate("a", .maybe, kindle: kindle)], zone: .gmt)

    let rows = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.label, $0) })

    #expect(
      rows["Author"]
        == ComparisonRow(
          label: "Author", library: "Herman Melville", kindle: "—", differs: false))
    #expect(
      rows["Publisher"]
        == ComparisonRow(
          label: "Publisher", library: "—", kindle: "—", differs: false))
    #expect(rows["ISBN"]?.differs == false)
  }

  @Test func marksDifferentAuthorsFormatsAndPDFSizes() {
    let kindle = KindleBook.fixture(
      path: "Moby-Dick - Herman Melville.pdf", authors: ["Someone Else"], byteCount: 900_000)
    let pdf = DuplicateCase(
      book: .fixture(format: .pdf), edition: nil,
      match: KindleMatch(book: kindle, confidence: .maybe, reason: .titleAndAuthor),
      replace: .unavailable)
    let epub = duplicate("a", .maybe, kindle: kindle)

    let pdfRows = Dictionary(
      uniqueKeysWithValues: DuplicateReviewModel(cases: [pdf], zone: .gmt).rows.map {
        ($0.label, $0)
      })
    let epubRows = Dictionary(
      uniqueKeysWithValues: DuplicateReviewModel(cases: [epub], zone: .gmt).rows.map {
        ($0.label, $0)
      })

    #expect(pdfRows["Author"]?.differs == true)
    #expect(pdfRows["Format"]?.library == "PDF")
    #expect(pdfRows["Format"]?.differs == false)
    #expect(
      pdfRows["Size"]
        == ComparisonRow(
          label: "Size", library: "1 MB", kindle: "900 KB", differs: true))
    #expect(epubRows["Format"]?.differs == true)
    #expect(epubRows["Size"]?.differs == false)
  }

  @Test func theNoteSaysWhatReplaceKeeps() {
    #expect(
      DuplicateReviewModel(cases: [duplicate("a", .sure)]).note
        == "Replace keeps your reading position: the new copy goes under the same file name.")
  }

  @Test func theNoteSaysWhatRemovingAnotherCopyLoses() {
    #expect(
      DuplicateReviewModel(cases: [duplicate("a", .sure, .removesOther)]).note
        == "Replace removes this copy with its reading position, bookmarks and highlights.")
    #expect(
      DuplicateReviewModel(
        cases: [duplicate("a", .sure, .removesOther, kindle: .fixture(source: .amazon))]
      ).note == "Replace removes only the download; the book stays in your Amazon library.")
  }
}
