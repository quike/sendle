import Foundation

/// How searches find words: ignoring case and accents.
package enum TextMatches {
  static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

  package static func contains(every words: [Substring], in text: String) -> Bool {
    words.allSatisfy { text.range(of: $0, options: options) != nil }
  }

  /// Every occurrence of every word, in order, with overlapping or touching ones merged.
  package static func ranges(of words: [Substring], in text: String) -> [Range<String.Index>] {
    var found: [Range<String.Index>] = []
    for word in words {
      var from = text.startIndex
      while from < text.endIndex,
        let range = text.range(of: word, options: options, range: from..<text.endIndex)
      {
        found.append(range)
        from = text.index(after: range.lowerBound)
      }
    }
    var merged: [Range<String.Index>] = []
    for range in found.sorted(by: { $0.lowerBound < $1.lowerBound }) {
      if let last = merged.last, range.lowerBound <= last.upperBound {
        merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
      } else {
        merged.append(range)
      }
    }
    return merged
  }
}
