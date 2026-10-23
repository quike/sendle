import Foundation

package enum XMLDeclarationFix {
  package static let declaration = #"<?xml version="1.0" encoding="utf-8"?>"#

  /// Adds a UTF-8 declaration, or completes one that names no encoding; nil when the document
  /// already names its encoding, because its bytes are in that encoding.
  package static func apply(to text: String) -> String? {
    let body = text.drop(while: \.isWhitespace)
    guard body.prefixMatch(of: #/<\?xml\s/#) != nil else { return declaration + "\n" + text }
    guard let end = body.range(of: "?>"), !body[..<end.upperBound].contains("encoding") else {
      return nil
    }
    return declaration + body[end.upperBound...]
  }
}
