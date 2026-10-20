import SendleDomain
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SortNamesTests {
  @Test(
    arguments: [
      ("Los ritos del agua", "es", "ritos del agua, Los"),
      ("The Hobbit", "en", "Hobbit, The"),
      ("El Principito", "es-ES", "Principito, El"),
      ("L'Étranger", "fr", "Étranger, L'"),
      ("Patria", "es", nil),
      ("The", "en", nil),  // nothing after the article
      ("La casa", "ja", nil),  // no article list for the language
      ("The Road", nil, "Road, The"),  // unknown language reads as English
    ] as [(String, String?, String?)])
  func sortTitlesDropOneLeadingArticle(title: String, language: String?, expected: String?) {
    #expect(SortNames.title(title, language: language) == expected)
  }

  @Test func sortNamesFlipTheLastWordAndKeepCommaForms() {
    #expect(SortNames.author("Eva García Sáenz") == "Sáenz, Eva García")
    #expect(SortNames.author("Tolkien, J. R. R.") == "Tolkien, J. R. R.")
    #expect(SortNames.author("Plato") == "Plato")
    #expect(SortNames.isSortForm("Cortázar, Julio"))
    #expect(!SortNames.isSortForm("Julio Cortázar"))
    #expect(!SortNames.isSortForm("A, B, C"))
    #expect(!SortNames.isSortForm(", Julio"))
    #expect(SortNames.isSingleWriter("Julio Cortázar"))
    #expect(!SortNames.isSingleWriter("Ann Smith & Bob Jones"))
    #expect(!SortNames.isSingleWriter("Ogas, Ogi; Gaddam, Sai"))
    #expect(SortNames.displayForm("Ejsmont, Artur") == "Artur Ejsmont")
    #expect(SortNames.displayForm("Ann Smith & Bob Jones") == "Ann Smith & Bob Jones")
  }

  @Test func sortTitlesKeepTheArticlesSpellingAndSticksElisionsToTheNextWord() {
    #expect(SortNames.title("L\u{2019}homme qui rit", language: "fr") == "homme qui rit, L\u{2019}")
    #expect(SortNames.title("l'  ", language: "fr") == nil)
    #expect(SortNames.title("L'Étranger", language: "en") == nil)
    #expect(SortNames.title("  die Welt ", language: "de-AT") == "Welt, die")
  }

  @Test func sortNamesLeaveSeveralWritersAsWritten() {
    #expect(SortNames.author("Ann Smith & Bob Jones") == "Ann Smith & Bob Jones")
    #expect(SortNames.author("Ogas, Ogi; Gaddam, Sai") == "Ogas, Ogi; Gaddam, Sai")
  }
}
