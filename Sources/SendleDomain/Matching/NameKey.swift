import Foundation

/// Reduces titles and author names to keys that match whatever their case, accents,
/// punctuation or word order.
public enum NameKey {
  private static let articles: Set<String> = [
    "the", "a", "an", "el", "la", "los", "las", "un", "una", "le", "les",
  ]
  private static let locale = Locale(identifier: "en_US_POSIX")

  public static func title(_ text: String) -> String {
    var folded = fold(text)
    for elision in ["l'", "l\u{2019}"] where folded.hasPrefix(elision) {
      let rest = folded.dropFirst(elision.count)
      if rest.contains(where: isKeyCharacter) { folded = String(rest) }
      break
    }
    var words = words(of: folded)
    if words.count > 1, articles.contains(words[0]) { words.removeFirst() }
    return words.joined()
  }

  public static func authors(_ names: [String]) -> Set<String> {
    var keys: Set<String> = []
    for name in names {
      let parts = name.replacingOccurrences(of: ";", with: " & ").components(separatedBy: " & ")
      for part in parts {
        let key = words(of: fold(personalOrder(part))).joined()
        if !key.isEmpty { keys.insert(key) }
      }
    }
    return keys
  }

  /// "Tolkien, J.R.R." reads as "J.R.R. Tolkien".
  private static func personalOrder(_ name: String) -> String {
    let pieces = name.components(separatedBy: ",")
    guard pieces.count == 2 else { return name }
    return pieces[1] + " " + pieces[0]
  }

  private static func fold(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
  }

  private static func words(of text: String) -> [String] {
    String(text.map { isKeyCharacter($0) ? $0 : " " })
      .split(separator: " ").map(String.init)
  }

  private static func isKeyCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber
  }
}
