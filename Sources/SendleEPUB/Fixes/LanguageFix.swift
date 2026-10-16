import Foundation

package enum LanguageFix {
  /// Adds a `dc:language` just before `</metadata>` when the package has none.
  package static func apply(to package: String, hasLanguage: Bool, language: String?) -> String? {
    guard !hasLanguage, let close = package.firstRange(of: #/<\/([\w.-]+:)?metadata\s*>/#) else {
      return nil
    }
    let element =
      #"<dc:language xmlns:dc="http://purl.org/dc/elements/1.1/">"# + code(for: language)
      + "</dc:language>\n"
    return package.replacingCharacters(in: close.lowerBound..<close.lowerBound, with: element)
  }

  /// `language` as a BCP 47 tag, or `en` when it isn't usable as one.
  static func code(for language: String?) -> String {
    guard let tag = language?.replacingOccurrences(of: "_", with: "-"),
      tag.wholeMatch(of: #/[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*/#) != nil
    else { return "en" }
    return tag
  }
}
