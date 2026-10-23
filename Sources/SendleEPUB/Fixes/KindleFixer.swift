import SendleDomain

/// Applies every Kindle fix to an EPUB's markup documents.
package struct KindleFixer: Sendable {
  package struct Result: Hashable, Sendable {
    /// The documents that changed, by archive path.
    package var documents: [String: String]
    package var fixes: [EPUBFix]
  }

  private static let contentTypes: Set = ["application/xhtml+xml", "text/html"]
  private static let markupTypes = contentTypes.union(["application/x-dtbncx+xml"])

  private let language: String?

  /// `language` goes into books that declare none; nil means `en`.
  package init(language: String?) {
    self.language = language
  }

  /// The documents the fixes read: the package document, the content documents and the NCX.
  package static func markupPaths(in package: EPUBPackage) -> [String] {
    var paths = [package.path]
    for item in package.items where markupTypes.contains(item.mediaType) {
      if !paths.contains(item.path) { paths.append(item.path) }
    }
    return paths
  }

  /// `documents` holds the text of the markup documents by archive path. Documents left out,
  /// such as ones that aren't UTF-8, are never changed.
  package func apply(to documents: [String: String], package: EPUBPackage) -> Result {
    var current = documents
    var applied: Set<EPUBFix> = []
    func update(_ path: String, _ fix: EPUBFix, _ repair: (String) -> String?) {
      guard let text = current[path], let repaired = repair(text) else { return }
      current[path] = repaired
      applied.insert(fix)
    }
    let markup = Self.markupPaths(in: package)
    let content = markup.filter { path in
      package.items.contains { $0.path == path && Self.contentTypes.contains($0.mediaType) }
    }

    for path in markup {
      update(path, .addedXMLDeclaration, XMLDeclarationFix.apply)
    }
    update(package.path, .addedLanguage) {
      LanguageFix.apply(to: $0, hasLanguage: package.hasLanguage, language: language)
    }
    var bodyIDs: [String: String] = [:]
    for path in content {
      bodyIDs[path] = current[path].flatMap(BodyIDLinkFix.bodyID)
    }
    for path in markup {
      update(path, .removedBodyIDLinks) {
        BodyIDLinkFix.apply(to: $0, at: path, bodyIDs: bodyIDs)
      }
    }
    for path in content {
      update(path, .removedEmptyImages, EmptyImageFix.apply)
    }

    return Result(
      documents: current.filter { documents[$0.key] != $0.value },
      fixes: EPUBFix.allCases.filter(applied.contains)
    )
  }
}
