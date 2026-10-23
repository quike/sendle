import Foundation

/// A package document parsed for editing. Every change goes through it, so it knows whether the
/// text needs writing again. Writing it back keeps the original text around the root element and
/// its line endings. `XMLDocument` keeps the whitespace before an element with the element, so a
/// removed element takes its line with it and an added one starts no new line.
final class PackageDocument {
  static let dublinCore = "http://purl.org/dc/elements/1.1/"
  static let opf = "http://www.idpf.org/2007/opf"

  /// Character references and entities are left out: `XMLDocument` writes a text holding one of
  /// them next to `&amp;` with a bare `&`.
  private static let options: XMLNode.Options = XMLNode.Options.nodePreserveAll
    .subtracting([.nodePreserveCharacterReferences, .nodePreserveEntities])
    .union(.nodeLoadExternalEntitiesNever)

  private let document: XMLDocument
  let root: XMLElement
  let metadata: XMLElement
  let manifest: XMLElement?
  private let prolog: Substring
  private let epilogue: Substring
  private let usesCRLF: Bool
  private(set) var isModified = false
  private lazy var ids = Set(
    ((try? document.nodes(forXPath: "//@id")) ?? []).compactMap(\.stringValue))

  /// Nil for text that isn't an XML package with metadata, or that declares an encoding other
  /// than UTF-8, which the edited text is written in.
  init?(_ text: String) {
    guard let document = try? XMLDocument(xmlString: text, options: Self.options),
      let root = document.rootElement(), let name = root.name,
      let metadata = root.child("metadata"),
      let start = Self.start(of: name, in: text),
      let end = Self.end(of: name, in: text)
    else { return nil }
    let prolog = text[..<start]
    guard Self.declaresUTF8(prolog) else { return nil }
    self.document = document
    self.root = root
    self.metadata = metadata
    self.manifest = root.child("manifest")
    self.prolog = prolog
    self.epilogue = text[end...]
    self.usesCRLF = text[start..<end].contains("\r\n")
  }

  /// The edited text, or nil when it wouldn't read back as the same package.
  var text: String? {
    let body = root.xmlString(options: Self.options)
    let text = String(prolog) + (usesCRLF ? body.replacing("\n", with: "\r\n") : body) + epilogue
    guard let reread = try? XMLDocument(xmlString: text, options: Self.options),
      reread.rootElement()?.name == root.name
    else { return nil }
    return text
  }

  var isEPUB3: Bool { root.attributeValue("version")?.hasPrefix("3") == true }

  /// Whether `element` is the identifier the package names as its unique one.
  func isUniqueIdentifier(_ element: XMLElement) -> Bool {
    guard let id = element.attributeValue("id") else { return false }
    return id == root.attributeValue("unique-identifier")
  }

  func dublinCore(_ name: String) -> [XMLElement] {
    metadata.elements(forLocalName: name, uri: Self.dublinCore)
  }

  /// `<meta name="…">`, as EPUB 2 writes it, or `<meta property="…">`, as EPUB 3 does.
  func metas(named name: String) -> [XMLElement] {
    metadata.childElements.filter {
      $0.localName == "meta"
        && ($0.attributeValue("name") == name || $0.attributeValue("property") == name)
    }
  }

  /// The `<meta refines="#id">` elements that describe `element`.
  func refinements(of element: XMLElement) -> [XMLElement] {
    guard let id = element.attributeValue("id") else { return [] }
    return metadata.childElements.filter {
      $0.localName == "meta" && $0.attributeValue("refines") == "#\(id)"
    }
  }

  func isTaken(id: String) -> Bool { ids.contains(id) }

  /// `base`, or `base-2`, `base-3`… when another element has that id.
  func unusedID(_ base: String) -> String {
    var id = base
    var number = 2
    while ids.contains(id) {
      id = "\(base)-\(number)"
      number += 1
    }
    ids.insert(id)
    return id
  }

  // MARK: New nodes

  func newDublinCore(_ name: String, text: String) -> XMLElement {
    let prefix = prefix(for: Self.dublinCore, preferring: "dc", allowsDefault: true)
    let element = XMLElement(name: Self.qualified(name, prefix), uri: Self.dublinCore)
    element.stringValue = Self.xmlCharacters(text)
    return element
  }

  /// An element in the package's own namespace, named the way `parent` is.
  func newElement(
    _ name: String, in parent: XMLElement, attributes: [(String, String)], text: String? = nil
  ) -> XMLElement {
    let element = XMLElement(name: Self.qualified(name, parent.prefix ?? ""), uri: parent.uri)
    for (name, value) in attributes {
      element.addAttribute(Self.attribute(name, value))
    }
    if let text { element.stringValue = Self.xmlCharacters(text) }
    return element
  }

  func newOPFAttribute(_ name: String, _ value: String) -> XMLNode {
    let prefix = prefix(for: Self.opf, preferring: "opf", allowsDefault: false)
    return Self.attribute(Self.qualified(name, prefix), value, uri: Self.opf)
  }

  static func attribute(_ name: String, _ value: String, uri: String? = nil) -> XMLNode {
    let attribute = XMLNode(kind: .attribute)
    attribute.name = name
    attribute.uri = uri
    attribute.stringValue = xmlCharacters(value)
    return attribute
  }

  // MARK: Changes

  func setText(_ text: String, of element: XMLElement) {
    let text = Self.xmlCharacters(text)
    guard element.stringValue != text else { return }
    element.stringValue = text
    isModified = true
  }

  /// Sets an attribute in no namespace, or removes it when `value` is nil.
  func setAttribute(_ name: String, _ value: String?, of element: XMLElement) {
    let value = value.map(Self.xmlCharacters)
    guard element.attributeValue(name) != value else { return }
    if let value, let existing = element.attribute(forName: name) {
      existing.stringValue = value
    } else if let value {
      element.addAttribute(Self.attribute(name, value))
    } else {
      element.removeAttribute(forName: name)
    }
    isModified = true
  }

  func removeOPFAttribute(_ name: String, from element: XMLElement) {
    guard let qualified = element.attribute(forLocalName: name, uri: Self.opf)?.name else {
      return
    }
    element.removeAttribute(forName: qualified)
    isModified = true
  }

  /// Gives `element` another local name, keeping its prefix.
  func rename(_ element: XMLElement, to localName: String) {
    let name = Self.qualified(localName, element.prefix ?? "")
    guard element.name != name else { return }
    element.name = name
    isModified = true
  }

  func remove(_ element: XMLElement) {
    element.detach()
    isModified = true
  }

  func insert(_ element: XMLElement, before anchor: XMLElement) {
    guard let parent = anchor.parent as? XMLElement else { return }
    parent.insertChild(element, at: anchor.index)
    isModified = true
  }

  func append(_ element: XMLElement, to parent: XMLElement) {
    parent.addChild(element)
    isModified = true
  }

  // MARK: Private

  /// A prefix bound to `uri` where the metadata is, declaring one there when there is none.
  private func prefix(for uri: String, preferring preferred: String, allowsDefault: Bool)
    -> String
  {
    if let prefix = metadata.resolvePrefix(forNamespaceURI: uri),
      allowsDefault || !prefix.isEmpty
    {
      return prefix
    }
    var prefix = preferred
    var number = 2
    while let bound = metadata.resolveNamespace(forName: "\(prefix):x") {
      if bound.stringValue == uri { return prefix }
      prefix = "\(preferred)\(number)"
      number += 1
    }
    let namespace = XMLNode(kind: .namespace)
    namespace.name = prefix
    namespace.stringValue = uri
    metadata.addNamespace(namespace)
    isModified = true
    return prefix
  }

  private static func qualified(_ name: String, _ prefix: String) -> String {
    prefix.isEmpty ? name : "\(prefix):\(name)"
  }

  /// `text` without the characters XML 1.0 can't hold, such as most C0 controls.
  private static func xmlCharacters(_ text: String) -> String {
    String(
      String.UnicodeScalarView(
        text.unicodeScalars.filter {
          switch $0.value {
          case 0x9, 0xA, 0xD, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: true
          default: false
          }
        }))
  }

  /// Where the root element's start tag begins: past the declaration, comments, processing
  /// instructions and doctype.
  private static func start(of name: String, in text: String) -> String.Index? {
    guard let start = skippingMisc(in: text, from: text.startIndex),
      text[start...].hasPrefix("<\(name)"),
      let next = text[start...].dropFirst(name.count + 1).first,
      next.isWhitespace || next == ">" || next == "/"
    else { return nil }
    return start
  }

  /// Just after the root element's end tag: the last one followed only by comments, processing
  /// instructions and whitespace.
  private static func end(of name: String, in text: String) -> String.Index? {
    for close in text.ranges(of: "</\(name)").reversed() {
      guard let bracket = text[close.upperBound...].firstIndex(of: ">") else { continue }
      let end = text.index(after: bracket)
      if skippingMisc(in: text, from: end) == text.endIndex { return end }
    }
    return nil
  }

  /// The first index from `index` that isn't whitespace, a byte order mark, a comment, a
  /// processing instruction or a doctype; nil inside one that never ends.
  private static func skippingMisc(in text: String, from index: String.Index) -> String.Index? {
    var index = index
    while index < text.endIndex {
      let rest = text[index...]
      if let first = rest.first, first.isWhitespace || first == "\u{FEFF}" {
        index = text.index(after: index)
      } else if rest.hasPrefix("<!--") {
        guard let close = rest.firstRange(of: "-->") else { return nil }
        index = close.upperBound
      } else if rest.hasPrefix("<?") {
        guard let close = rest.firstRange(of: "?>") else { return nil }
        index = close.upperBound
      } else if rest.hasPrefix("<!DOCTYPE") {
        guard let close = endOfDoctype(rest) else { return nil }
        index = close
      } else {
        break
      }
    }
    return index
  }

  /// Just after a doctype's closing `>`, past its quoted strings and internal subset.
  private static func endOfDoctype(_ text: Substring) -> String.Index? {
    var quote: Character?
    var depth = 0
    for index in text.indices {
      let character = text[index]
      if let open = quote {
        if character == open { quote = nil }
      } else if character == "\"" || character == "'" {
        quote = character
      } else if character == "[" {
        depth += 1
      } else if character == "]" {
        depth -= 1
      } else if character == ">", depth == 0 {
        return text.index(after: index)
      }
    }
    return nil
  }

  private static func declaresUTF8(_ prolog: Substring) -> Bool {
    let encoding = #/<\?xml\s[^>]*?encoding\s*=\s*["']([^"']*)["']/#
    guard let declared = prolog.firstMatch(of: encoding)?.output.1 else { return true }
    return ["utf-8", "utf8"].contains(declared.lowercased())
  }
}

extension XMLElement {
  var childElements: [XMLElement] {
    (children ?? []).compactMap { $0 as? XMLElement }
  }

  fileprivate func child(_ localName: String) -> XMLElement? {
    childElements.first { $0.localName == localName }
  }

  func attributeValue(_ attribute: String) -> String? {
    self.attribute(forName: attribute)?.stringValue
  }

  func opfAttributeValue(_ attribute: String) -> String? {
    self.attribute(forLocalName: attribute, uri: PackageDocument.opf)?.stringValue
  }
}
