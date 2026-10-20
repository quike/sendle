import Foundation

/// Derives the sort forms of titles and authors that Books and the Kindle file them under.
public enum SortNames {
  private static let articles: [String: [String]] = [
    "en": ["the", "a", "an"],
    "es": ["el", "la", "los", "las", "un", "una", "unos", "unas"],
    "fr": ["le", "la", "les", "un", "une", "l'"],
    "de": ["der", "die", "das", "ein", "eine"],
    "it": ["il", "lo", "la", "i", "gli", "le", "un", "uno", "una", "l'"],
    "pt": ["o", "a", "os", "as", "um", "uma"],
    "ca": ["el", "la", "els", "les", "l'"],
  ]
  private static let elisions = ["'", "\u{2019}"]

  /// "Los ritos del agua" files as "ritos del agua, Los". Nil when the title has no leading
  /// article in the language's list; an unknown or missing language reads as English.
  public static func title(_ title: String, language: String?) -> String? {
    let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let list = articles[primaryLanguage(of: language)] else { return nil }

    if list.contains("l'") {
      for apostrophe in elisions {
        let article = text.prefix(1 + apostrophe.count)
        guard article.lowercased() == "l" + apostrophe else { continue }
        return moved(article, from: text.dropFirst(article.count))
      }
    }

    let words = text.split(maxSplits: 1, whereSeparator: \.isWhitespace)
    guard words.count == 2, list.contains(words[0].lowercased()) else { return nil }
    return moved(words[0], from: words[1])
  }

  /// "Eva García Sáenz" files as "Sáenz, Eva García"; "Tolkien, J. R. R." is already a sort name.
  public static func author(_ author: String) -> String {
    let text = author.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isSingleWriter(text), !isSortForm(text) else { return text }
    let words = text.split(whereSeparator: \.isWhitespace)
    guard let surname = words.last, words.count > 1 else { return text }
    return "\(surname), \(words.dropLast().joined(separator: " "))"
  }

  /// Exactly one comma, with something on both sides.
  public static func isSortForm(_ text: String) -> Bool {
    let pieces = text.components(separatedBy: ",")
    return pieces.count == 2
      && pieces.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  }

  public static func isSingleWriter(_ author: String) -> Bool {
    !author.contains("&") && !author.contains(";")
  }

  /// "Ejsmont, Artur" reads as "Artur Ejsmont"; anything else is left as written.
  public static func displayForm(_ author: String) -> String {
    guard isSingleWriter(author), isSortForm(author) else { return author }
    return author.components(separatedBy: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .reversed()
      .joined(separator: " ")
  }

  private static func primaryLanguage(of language: String?) -> String {
    let tag = language?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    guard let primary = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first else {
      return "en"
    }
    return String(primary)
  }

  private static func moved(_ article: Substring, from rest: Substring) -> String? {
    let remainder = rest.trimmingCharacters(in: .whitespacesAndNewlines)
    return remainder.isEmpty ? nil : "\(remainder), \(article)"
  }
}
