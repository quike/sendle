import SendleDomain
import SendleTestSupport
import Testing

struct KindleBookTests {
  @Test(
    arguments: [
      (
        "Downloads/Items01/Pride and Prejudice - Jane Austen_OLE6OR2WWT5NC3Z6D6AXPK74XXPLQZ2V.kfx",
        "Pride and Prejudice", ["Jane Austen"], "OLE6OR2WWT5NC3Z6D6AXPK74XXPLQZ2V"
      ),
      (
        "Downloads/Items01/Bleak House_0123456789ABCDEF0123456789ABCDEF.kfx",
        "Bleak House", [], "0123456789ABCDEF0123456789ABCDEF"
      ),
      ("Downloads/Items01/The Hobbit_B007978NPG.kfx", "The Hobbit", [], "B007978NPG"),
      (
        "Star Wars - A New Hope - George Lucas.txt", "Star Wars - A New Hope", ["George Lucas"], nil
      ),
      ("my_notes.txt", "my_notes", [], nil),
      ("Abreu, Andrea/Panza de burro - Andrea Abreu.azw3", "Panza de burro", ["Andrea Abreu"], nil),
    ] as [(String, String, [String], String?)])
  func readsTitleAuthorAndIDFromAFileName(
    path: String, title: String, authors: [String], id: String?
  ) {
    let parsed = KindleFileName.parse(path)
    #expect(parsed.title == title)
    #expect(parsed.authors == authors)
    #expect(parsed.amazonID == id)
  }

  @Test func theNameIsTheStemWithoutTheID() {
    #expect(
      KindleFileName.parse(
        "Downloads/Items01/Star Wars - A New Hope_0123456789ABCDEF0123456789ABCDEF.kfx"
      ).name == "Star Wars - A New Hope")
  }

  @Test(
    arguments: [
      (
        "Alice's Adventures in Wonderland - Lewis Carroll.azw3", "SN5T2DYX77", false,
        KindleBookSource.sendle
      ),
      ("Downloads/Items01/Bleak House_0123456789ABCDEF0123456789ABCDEF.kfx", nil, false, .email),
      (
        "Downloads/Items01/Pride and Prejudice - Jane Austen_OLE6OR2WWT5NC3Z6D6AXPK74XXPLQZ2V.kfx",
        "B088BBLMGS", false, .email
      ),
      ("Panza de burro.azw3", "0231b0ed-1c4e-4f3b-9a6e-2d5c7f1e8a90", false, .calibre),
      ("Abreu, Andrea/Panza de burro - Andrea Abreu.azw3", nil, true, .calibre),
      ("Abreu, Andrea/Panza de burro - Andrea Abreu.azw3", nil, false, .byHand),
      ("Dune.azw3", "B088BBLMGS", false, .amazon),
      ("Downloads/Items01/The Hobbit_B007978NPG.kfx", nil, false, .amazon),
      ("Notes.txt", nil, true, .byHand),
    ] as [(String, String?, Bool, KindleBookSource)])
  func tellsWhereABookCameFrom(
    path: String, asin: String?, calibre: Bool, source: KindleBookSource
  ) {
    #expect(
      KindleBookSource.detect(relativePath: path, asin: asin, calibreLibrary: calibre) == source)
  }

  @Test func aBookKnowsItsFormatAndPlace() {
    let book = KindleBook.fixture(path: "Abreu, Andrea/Panza de burro - Andrea Abreu.AZW3")
    #expect(book.format == "azw3")
    #expect(book.stem == "Panza de burro - Andrea Abreu")
    #expect(
      book.url(on: .fixture()).path
        == "/Volumes/Kindle/documents/Abreu, Andrea/Panza de burro - Andrea Abreu.AZW3")
  }
}
