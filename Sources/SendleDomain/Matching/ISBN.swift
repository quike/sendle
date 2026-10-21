import Foundation

public enum ISBN {
  /// The ISBN-13 digits for a valid ISBN-10 or ISBN-13 in any common spelling, or nil.
  public static func normalised(_ text: String) -> String? {
    let characters = characters(of: text)
    switch characters.count {
    case 10: return thirteen(fromTen: characters)
    case 13: return isValidThirteen(characters) ? characters : nil
    default: return nil
    }
  }

  /// Ten digits, the last of which may be an X, or thirteen, in any common spelling, whether or
  /// not the check digit matches.
  public static func hasISBNDigits(_ text: String) -> Bool {
    let characters = Array(characters(of: text))
    let isDigit = { (character: Character) in character.isASCII && character.isNumber }
    switch characters.count {
    case 10:
      return characters.dropLast().allSatisfy(isDigit)
        && (isDigit(characters[9]) || characters[9] == "x")
    case 13: return characters.allSatisfy(isDigit)
    default: return false
    }
  }

  /// Lowercased, without its prefix, hyphens and spaces.
  private static func characters(of text: String) -> String {
    var rest = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for prefix in ["urn:isbn:", "isbn-13:", "isbn-10:", "isbn:", "isbn"]
    where rest.hasPrefix(prefix) {
      rest.removeFirst(prefix.count)
      break
    }
    let hyphens: Set<Character> = ["-", "\u{2010}", "\u{2011}"]
    return rest.filter { !$0.isWhitespace && !hyphens.contains($0) }
  }

  private static func thirteen(fromTen text: String) -> String? {
    let characters = Array(text)
    var values: [Int] = []
    for (index, character) in characters.enumerated() {
      if index == 9, character == "x" {
        values.append(10)
      } else if character.isASCII, let digit = character.wholeNumberValue {
        values.append(digit)
      } else {
        return nil
      }
    }
    let sum = values.enumerated().reduce(0) { $0 + (10 - $1.offset) * $1.element }
    guard sum % 11 == 0 else { return nil }
    let core = "978" + String(characters[..<9])
    return core + String((10 - weightedSum(core) % 10) % 10)
  }

  private static func isValidThirteen(_ text: String) -> Bool {
    guard text.allSatisfy({ $0.isASCII && $0.isNumber }),
      text.hasPrefix("978") || text.hasPrefix("979")
    else { return false }
    return weightedSum(text) % 10 == 0
  }

  private static func weightedSum(_ digits: String) -> Int {
    digits.enumerated().reduce(0) {
      $0 + ($1.element.wholeNumberValue ?? 0) * ($1.offset % 2 == 0 ? 1 : 3)
    }
  }
}
