import Foundation

public enum FileNaming {
  public static let maxLength = 120

  /// "Title - Author" as plain ASCII without path characters, so every mail server and
  /// file system accepts it.
  public static func baseName(for book: Book) -> String {
    let parts = [book.title, book.author ?? ""].map(portable).filter { !$0.isEmpty }
    let shortened = String(parts.joined(separator: " - ").prefix(maxLength))
      .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    return shortened.isEmpty ? "Book" : shortened
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
    return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
  }
}
