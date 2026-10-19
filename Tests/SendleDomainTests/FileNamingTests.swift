import SendleDomain
import SendleTestSupport
import Testing

struct FileNamingTests {
  @Test(arguments: [
    ("Moby-Dick", "Herman Melville", "Moby-Dick - Herman Melville"),
    ("Les Misérables", "Victor Hugo", "Les Miserables - Victor Hugo"),
    ("AC/DC: Live?", nil, "AC DC Live"),
    ("  Spaced   out  ", "", "Spaced out"),
    (".hidden", nil, "hidden"),
    ("   ", nil, "Book"),
    ("Ender’s Game", "Orson Scott Card", "Ender's Game - Orson Scott Card"),
    ("Straße", "Søren Kierkegaard", "Strasse - Soren Kierkegaard"),
    ("Łódź", nil, "Lodz"),
    ("", "Anon", "Anon"),
    ("a\u{7F}b", nil, "a b"),
  ])
  func makesPortableNames(title: String, author: String?, expected: String) {
    #expect(FileNaming.baseName(for: .fixture(title: title, author: author)) == expected)
  }

  @Test func transliteratesNonLatinScripts() {
    let name = FileNaming.baseName(for: .fixture(title: "Война и мир", author: "Лев Толстой"))
    #expect(name.unicodeScalars.allSatisfy { $0.isASCII })
    #expect(name.contains(" - "))
  }

  @Test func capsTheLength() {
    let name = FileNaming.baseName(for: .fixture(title: String(repeating: "a", count: 300)))
    #expect(name.count == FileNaming.maxLength)
  }

  // MARK: Delivery names

  @Test(arguments: [
    ("Moby-Dick", "Herman Melville", "Moby-Dick"),
    ("Édité", "Anne Auteur", "Édité"),
    ("Dune: Messiah", nil, "Dune: Messiah"),
    ("Война и мир", "Лев Толстой", "Война и мир"),
    ("Do Androids Dream of \"Sheep\"?", nil, "Do Androids Dream of \"Sheep\"?"),
    ("AC/DC \\ Live", nil, "AC DC Live"),
    ("Line\nbreak\u{7}\u{85}", nil, "Line break"),
    ("  .hidden.  ", nil, "hidden"),
    ("/", "Anon", "Book"),
  ])
  func namesAnEmailedBookAfterItsTitleAlone(title: String, author: String?, expected: String) {
    let book = Book.fixture(title: title, author: author)
    #expect(FileNaming.deliveryName(for: book, to: .email) == expected)
  }

  @Test func composesAccentsInEmailNames() {
    let name = FileNaming.deliveryName(for: .fixture(title: "E\u{301}dite\u{301}"), to: .email)
    #expect(Array(name.unicodeScalars) == Array("\u{C9}dit\u{E9}".unicodeScalars))
  }

  @Test func capsEmailNamesInBytesOnWholeCharacters() {
    let title = "a" + String(repeating: "é", count: 200)
    let name = FileNaming.deliveryName(for: .fixture(title: title), to: .email)
    #expect(name == "a" + String(repeating: "é", count: 119))
    #expect(name.utf8.count <= FileNaming.maxEmailNameBytes)
  }

  @Test func keepsThePortableNameForUSB() {
    let book = Book.fixture(title: "Édité: Suite", author: "Anne Auteur")
    #expect(FileNaming.deliveryName(for: book, to: .usb) == FileNaming.baseName(for: book))
  }

  @Test func theASINSeedCarriesTheEditionKeyOrTheName() {
    let moby = Book.fixture()
    #expect(
      FileNaming.asinSeed(for: moby, edition: Edition(key: " urn:uuid:moby-dick "), copy: 1)
        == "edition:urn:uuid:moby-dick")
    #expect(
      FileNaming.asinSeed(for: moby, edition: Edition(key: "urn:uuid:moby-dick"), copy: 2)
        == "edition:urn:uuid:moby-dick#2")
    #expect(
      FileNaming.asinSeed(for: moby, edition: nil, copy: 1) == "Moby-Dick - Herman Melville")
    #expect(
      FileNaming.asinSeed(for: moby, edition: Edition(key: ""), copy: 3)
        == "Moby-Dick - Herman Melville (3)")
  }
}
