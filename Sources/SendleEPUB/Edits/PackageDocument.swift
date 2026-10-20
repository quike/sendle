import Foundation

/// A package document parsed for editing. Writing it back keeps the original text around the root
/// element and its line endings. `XMLDocument` keeps the whitespace before an element with the
/// element, so a removed element takes its line with it and an added one starts no new line.
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
  private lazy var ids = Set(
    ((try? document.nodes(forXPath: "//@id")) ?? []).compactMap(\.stringValue))

  /// Nil for text that isn't an XML package with metadata, or that declares an encoding other
  /// than UTF-8, which the edited text is written in.
  init?(_ text: String) {
    guard let document = try? XMLDocument(xmlString: text, options: Self.options),
      let root = document.rootElement(), let name = root.name,
      let metadata = root.child("metadata"),
      let start = Self.start(of: name, in: text)
    else { return nil }
    let prolog = text[..<start]
    guard Self.declaresUTF8(prolog) else { return nil }
    self.document = document
    self.root = root
    self.metadata = metadata
    self.manifest = root.child("manifest")
    self.prolog = prolog
    self.epilogue = Self.end(of: name, in: text).map { text[$0...] } ?? ""
    self.usesCRLF = text[start...].contains("\r\n")
  }

  var text: String {
    let body = root.xmlString(options: Self.options)
    return prolog + (usesCRLF ? body.replacing("\n", with: "\r\n") : body) + epilogue
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

  func metas(named name: String) -> [XMLElement] {
    metadata.childElements.filter { $0.localName == "meta" && $0.attributeValue("name") == name }
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
    element.stringValue = text
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
    if let text { element.stringValue = text }
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
    attribute.stringValue = value
    return attribute
  }

  // MARK: Moving nodes

  /// Gives `element` another local name, keeping its prefix.
  func rename(_ element: XMLElement, to localName: String) {
    element.name = Self.qualified(localName, element.prefix ?? "")
  }

  func insert(_ element: XMLElement, before anchor: XMLElement) {
    (anchor.parent as? XMLElement)?.insertChild(element, at: anchor.index)
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
    return prefix
  }

  private static func qualified(_ name: String, _ prefix: String) -> String {
    prefix.isEmpty ? name : "\(prefix):\(name)"
  }

  /// Where the root element's start tag begins.
  private static func start(of name: String, in text: String) -> String.Index? {
    text.ranges(of: "<\(name)").first { range in
      text[range.upperBound...].first.map { $0.isWhitespace || $0 == ">" || $0 == "/" } ?? false
    }?.lowerBound
  }

  /// Just after the root element's end tag.
  private static func end(of name: String, in text: String) -> String.Index? {
    guard let close = text.ranges(of: "</\(name)").last,
      let bracket = text[close.upperBound...].firstIndex(of: ">")
    else { return nil }
    return text.index(after: bracket)
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

  func removeOPFAttribute(_ name: String) {
    guard let qualified = attribute(forLocalName: name, uri: PackageDocument.opf)?.name else {
      return
    }
    removeAttribute(forName: qualified)
  }
}
