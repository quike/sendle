import Foundation

package enum EmptyImageFix {
  /// Removes `<img>` tags whose `src` is missing or blank.
  package static func apply(to text: String) -> String? {
    var changed = false
    let fixed = text.replacing(
      #/<img\b(?:[^>"']|"[^"]*"|'[^']*')*>(?:\s*<\/img\s*>)?/#.ignoresCase()
    ) { match in
      let tag = match.output
      let source = tag.firstMatch(of: #/\ssrc\s*=\s*(["'])(.*?)\1/#.ignoresCase())
      if let source, !source.output.2.trimmingCharacters(in: .whitespaces).isEmpty {
        return String(tag)
      }
      changed = true
      return ""
    }
    return changed ? fixed : nil
  }
}
