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
}
