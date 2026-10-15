import Foundation

public enum FileNaming {
  public static let maxLength = 120

  /// "Title - Author" as plain ASCII without path characters, so every mail server and
  /// file system accepts it.
  public static func baseName(for book: Book) -> String {
    var name = book.title
    if let author = book.author, !author.isEmpty {
      name += " - \(author)"
    }
    let latin = name.applyingTransform(.toLatin, reverse: false) ?? name
    let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    let forbidden = Set("/\\:*?\"<>|")
    let cleaned = String(
      plain.unicodeScalars.map { scalar -> Character in
        let character = Character(scalar)
        guard scalar.isASCII, scalar.value >= 0x20, !forbidden.contains(character) else {
          return " "
        }
        return character
      }
    )
    let collapsed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    let shortened = String(trimmed.prefix(maxLength))
      .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    return shortened.isEmpty ? "Book" : shortened
  }
}
