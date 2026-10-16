import Foundation
import SendleDomain

/// Spots DRM by what it leaves in `META-INF`: FairPlay's `sinf.xml`, Adobe's `rights.xml`, or an
/// `encryption.xml` that encrypts more than fonts.
public struct EPUBProtectionInspector: ProtectionInspector {
  public init() {}

  /// Only unzipped EPUB folders are inspected here; `KindleEPUBPreparer` checks zipped ones
  /// after unzipping them.
  public func isProtected(_ book: Book) -> Bool {
    var isDirectory: ObjCBool = false
    guard book.format == .epub,
      FileManager.default.fileExists(
        atPath: book.fileURL.path(percentEncoded: false), isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return false }
    return Self.hasDRMEvidence(in: book.fileURL)
  }

  package static func hasDRMEvidence(in root: URL) -> Bool {
    let metaInf = root.appending(path: "META-INF", directoryHint: .isDirectory)
    func exists(_ name: String) -> Bool {
      FileManager.default.fileExists(
        atPath: metaInf.appending(path: name).path(percentEncoded: false))
    }
    if exists("sinf.xml") || exists("rights.xml") { return true }
    guard exists("encryption.xml") else { return false }
    guard let manifest = BookFile.contents(of: metaInf.appending(path: "encryption.xml")) else {
      return true
    }
    return EncryptionManifest.encryptsMoreThanFonts(manifest)
  }
}

enum EncryptionManifest {
  private static let fontObfuscation: Set = [
    "http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#RC",
  ]
  private static let fontExtensions: Set = ["otf", "ttf", "woff", "woff2"]

  /// True when anything but a font is encrypted, or when the manifest can't be read.
  static func encryptsMoreThanFonts(_ data: Data) -> Bool {
    let reader = EncryptionReader()
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities = false
    parser.delegate = reader
    guard parser.parse() else { return true }
    return reader.entries.contains { entry in
      let target = NSString(string: entry.target ?? "").pathExtension.lowercased()
      return !fontObfuscation.contains(entry.algorithm ?? "") && !fontExtensions.contains(target)
    }
  }
}

private final class EncryptionReader: NSObject, XMLParserDelegate {
  struct Entry {
    var algorithm: String?
    var target: String?
  }

  var entries: [Entry] = []
  private var current: Entry?

  func parser(
    _ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    switch element {
    case "EncryptedData": current = Entry()
    case "EncryptionMethod" where current?.algorithm == nil:
      current?.algorithm = attributes["Algorithm"]
    case "CipherReference" where current?.target == nil: current?.target = attributes["URI"]
    default: break
    }
  }

  func parser(
    _ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
    qualifiedName: String?
  ) {
    guard element == "EncryptedData", let entry = current else { return }
    entries.append(entry)
    current = nil
  }
}
