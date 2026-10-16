import Foundation

package enum BodyIDLinkFix {
  /// The `id` of the document's `<body>`, if it has one.
  package static func bodyID(in text: String) -> String? {
    guard let body = text.firstMatch(of: #/<body\b(?:[^>"']|"[^"]*"|'[^']*')*>/#.ignoresCase())
    else { return nil }
    return body.output.firstMatch(of: #/\sid\s*=\s*(["'])(.*?)\1/#).map { String($0.output.2) }
  }

  /// Drops the fragment from `href` and `src` references that point at a `<body>` ID, which
  /// Amazon's converter rejects. `bodyIDs` maps each content document's path to its body ID.
  package static func apply(to text: String, at path: String, bodyIDs: [String: String])
    -> String?
  {
    let directory = ArchivePath.directory(of: path)
    let file = path.split(separator: "/").last.map(String.init) ?? path
    let name = file.addingPercentEncoding(withAllowedCharacters: unreserved) ?? file
    var changed = false
    let fixed = text.replacing(
      #/(?<lead>\b(?:href|src)\s*=\s*)(?<quote>["'])(?<target>[^"'#]*)#(?<id>[^"']*)\k<quote>/#
    ) { match in
      let target = String(match.target)
      let fragment = String(match.id)
      let resolved = target.isEmpty ? path : ArchivePath.resolve(target, from: directory)
      guard let resolved, let bodyID = bodyIDs[resolved],
        bodyID == fragment || bodyID == fragment.removingPercentEncoding
      else { return String(match.output.0) }
      changed = true
      return "\(match.lead)\(match.quote)\(target.isEmpty ? name : target)\(match.quote)"
    }
    return changed ? fixed : nil
  }
}

private let unreserved = CharacterSet(
  charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
