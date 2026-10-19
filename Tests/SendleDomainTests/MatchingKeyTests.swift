import SendleDomain
import Testing

struct MatchingKeyTests {
  @Test(arguments: [
    ("978-0-306-40615-7", "9780306406157"), ("urn:isbn:0306406152", "9780306406157"),
    ("ISBN 0-8044-2957-X", "9780804429573"), ("0141439513", "9780141439518"),
  ])
  func normalisesISBNsToThirteenDigits(text: String, isbn: String) {
    #expect(ISBN.normalised(text) == isbn)
  }

  @Test(arguments: ["0306406153", "9780306406158", "B088BBLMGS", "", "urn:uuid:moby-dick"])
  func refusesWhatIsNotAnISBN(text: String) {
    #expect(ISBN.normalised(text) == nil)
  }

  @Test func titlesMatchWhateverTheirCaseAccentsPunctuationAndArticle() {
    #expect(NameKey.title("The Hobbit") == NameKey.title("hobbit"))
    #expect(NameKey.title("¡Ay, Carmela!") == NameKey.title("Ay Carmela"))
    #expect(NameKey.title("Émile") == NameKey.title("EMILE"))
    #expect(NameKey.title("Ñandú y otros cuentos") == NameKey.title("Nandu y otros cuentos"))
    #expect(NameKey.title("El Quijote") == NameKey.title("Quijote"))
    #expect(NameKey.title("Moby-Dick") == NameKey.title("Moby Dick"))
    #expect(NameKey.title("The") == "the")
    #expect(NameKey.title("Moby-Dick; or, The Whale") != NameKey.title("Moby-Dick"))
  }

  @Test func authorsMatchInEitherOrder() {
    #expect(NameKey.authors(["Tolkien, J.R.R."]) == NameKey.authors(["J. R. R. Tolkien"]))
    #expect(NameKey.authors(["Bronte, Charlotte"]) == NameKey.authors(["Charlotte Brontë"]))
    #expect(
      NameKey.authors(["Terry Pratchett & Neil Gaiman"]) == ["terrypratchett", "neilgaiman"])
    #expect(NameKey.authors(["", "  "]).isEmpty)
  }
}
