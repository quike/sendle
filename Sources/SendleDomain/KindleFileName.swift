/// What a Kindle file name says about the book: "Title - Author", optionally followed by the
/// `_<id>` Amazon appends to downloads.
public enum KindleFileName {
  public struct Parsed: Hashable, Sendable {
    public let title: String
    public let authors: [String]
    public let amazonID: String?
    /// The stem without its `_<id>`.
    public let name: String
  }

  public static func parse(_ relativePath: String) -> Parsed {
    let fileName = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    let stem = stem(of: fileName)
    var name = stem
    var amazonID: String?
    if let underscore = stem.lastIndex(of: "_"), underscore != stem.startIndex {
      let candidate = stem[stem.index(after: underscore)...]
      if [10, 32].contains(candidate.count), candidate.allSatisfy(isUppercaseAlphanumeric) {
        amazonID = String(candidate)
        name = String(stem[..<underscore])
      }
    }
    if let dash = name.range(of: " - ", options: .backwards) {
      let title = String(name[..<dash.lowerBound])
      let author = String(name[dash.upperBound...])
      if !title.isEmpty, !author.isEmpty {
        return Parsed(title: title, authors: [author], amazonID: amazonID, name: name)
      }
    }
    return Parsed(title: name, authors: [], amazonID: amazonID, name: name)
  }

  static func stem(of fileName: String) -> String {
    guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else {
      return fileName
    }
    return String(fileName[..<dot])
  }

  private static func isUppercaseAlphanumeric(_ character: Character) -> Bool {
    character.isASCII && (character.isUppercase || character.isNumber)
  }
}
