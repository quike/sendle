import Foundation

public enum FileNaming {
  public static let maxLength = 120
  /// Leaves room for the extension within a 255-byte file name.
  public static let maxEmailNameBytes = 240

  /// Send to Kindle lists an emailed document under its attachment name, so email gets the
  /// title alone. USB keeps the portable name, which its ASIN derives from.
  public static func deliveryName(for book: Book, to destination: DestinationKind) -> String {
    switch destination {
    case .email: title(of: book)
    case .usb: baseName(for: book)
    }
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
