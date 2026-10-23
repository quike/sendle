import Foundation

public enum FileNaming {
  public static let maxLength = 120
  /// Leaves room for the extension within a 255-byte file name.
  public static let maxEmailNameBytes = 240
  /// How many copies of an edition are recognised by ASIN: the original and its Keep both copies.
  public static let editionCopyLimit = 9

  /// Send to Kindle lists an emailed document under its attachment name, so email gets the
  /// title alone. USB keeps the portable name, which its ASIN derives from.
  public static func deliveryName(for book: Book, to destination: DestinationKind) -> String {
    switch destination {
    case .email: title(of: book)
    case .usb: baseName(for: book)
    }
  }

  /// The text a delivered AZW3's ASIN derives from. An edition key makes the ASIN follow the
  /// edition, whatever the file is named; copy n of a book is numbered from 2.
  public static func asinSeed(for book: Book, edition: Edition?, copy: Int) -> String {
    if let key = edition?.trimmedKey {
      return copy < 2 ? "edition:" + key : "edition:" + key + "#\(copy)"
    }
    return copyName(for: book, copy: copy)
  }

  /// "Title - Author", or "Title - Author (n)" for Keep both copy n from 2.
  public static func copyName(for book: Book, copy: Int) -> String {
    copy < 2 ? baseName(for: book) : baseName(for: book) + " (\(copy))"
  }

  /// The smallest copy number from 2 whose name isn't in `taken`, a set of lowercased stems.
  public static func nextFreeCopy(for book: Book, taken: Set<String>) -> Int {
    var copy = 2
    while taken.contains(copyName(for: book, copy: copy).lowercased()) { copy += 1 }
    return copy
  }

  /// True when the Kindle book sits at the top of `documents/` under the name Sendle gives
  /// this book.
  public static func isSendlesCopy(_ kindleBook: KindleBook, of book: Book) -> Bool {
    let format = book.format == .epub ? "azw3" : "pdf"
    return kindleBook.id.relativePath.lowercased()
      == "\(baseName(for: book)).\(format)".lowercased()
  }

  /// "Title - Author" as plain ASCII without path characters, so every file system accepts it.
  public static func baseName(for book: Book) -> String {
    let parts = [book.title, book.author ?? ""].map(portable).filter { !$0.isEmpty }
    let shortened = tidy(String(parts.joined(separator: " - ").prefix(maxLength)))
    return shortened.isEmpty ? "Book" : shortened
  }

  /// The title in composed Unicode without path or control characters; mail headers encode it.
  private static func title(of book: Book) -> String {
    let cleaned = String(
      book.title.precomposedStringWithCanonicalMapping.unicodeScalars.map { scalar -> Character in
        scalar.properties.generalCategory == .control || scalar == "/" || scalar == "\\"
          ? " " : Character(scalar)
      }
    )
    var bytes = 0
    let shortened = tidy(cleaned).prefix { character in
      bytes += character.utf8.count
      return bytes <= maxEmailNameBytes
    }
    let name = tidy(String(shortened))
    return name.isEmpty ? "Book" : name
  }

  private static func portable(_ text: String) -> String {
    let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
    let ascii = latin.applyingTransform(StringTransform("Latin-ASCII"), reverse: false) ?? latin
    let forbidden = Set("/\\:*?\"<>|")
    let cleaned = String(
      ascii.unicodeScalars.map { scalar -> Character in
        let character = Character(scalar)
        guard (0x20..<0x7F).contains(scalar.value), !forbidden.contains(character) else {
          return " "
        }
        return character
      }
    )
    return tidy(cleaned)
  }

  /// Single spaces, and no spaces or dots at either end.
  private static func tidy(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
  }
}
