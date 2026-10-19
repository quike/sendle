import Foundation
import SendleDomain

/// Packages a book as an EPUB Amazon accepts: `mimetype` first and stored, Apple's additions left
/// out, and the Kindle fixes applied. Books' own files are only read.
public struct KindleEPUBPreparer: EPUBPreparer {
  private let extractor: any ArchiveExtractor = DittoExtractor()

  public init() {}

  public func prepare(_ book: Book, in staging: URL) async throws(SendFailure) -> PreparedFile {
    let root = try source(of: book, in: staging)
    if EPUBProtectionInspector.hasDRMEvidence(in: root) { throw .protected }
    guard let package = OPFReader.package(inEPUBAt: root) else {
      throw .invalidBook("Its package document is missing or unreadable")
    }
    let entries = EPUBContents.entries(in: root)
    let texts = Self.texts(of: KindleFixer.markupPaths(in: package), in: root, among: entries)
    let fixed = KindleFixer(language: book.language).apply(to: texts, package: package)
    let output = staging.appending(path: FileNaming.baseName(for: book) + ".epub")
    try Self.zip(entries, from: root, replacing: fixed.documents, to: output)
    return PreparedFile(
      url: output, format: .epub, fixes: fixed.fixes, edition: package.edition)
  }

  /// The book's folder, or a zipped `.epub` unzipped into `staging`.
  private func source(of book: Book, in staging: URL) throws(SendFailure) -> URL {
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: book.fileURL.path(percentEncoded: false), isDirectory: &isDirectory)
    else { throw .missing }
    if isDirectory.boolValue { return book.fileURL }
    let folder = staging.appending(path: "source", directoryHint: .isDirectory)
    try extractor.extract(book.fileURL, into: folder)
    return folder
  }

  /// The UTF-8 text of each of `paths` that is among the book's files.
  private static func texts(of paths: [String], in root: URL, among entries: [String])
    -> [String: String]
  {
    let present = Set(entries)
    var texts: [String: String] = [:]
    for path in paths where present.contains(path) {
      guard let data = try? Data(contentsOf: root.appending(path: path)),
        let text = String(data: data, encoding: .utf8), !text.contains("\0")
      else { continue }
      texts[path] = text
    }
    return texts
  }

  private static func zip(
    _ entries: [String],
    from root: URL,
    replacing documents: [String: String],
    to output: URL
  ) throws(SendFailure) {
    let writer = try writing { () throws(ZipError) in try ZipWriter(creatingFileAt: output) }
    try writing { () throws(ZipError) in
      try writer.add("mimetype", data: Data("application/epub+zip".utf8), method: .stored)
    }
    for path in entries {
      if Task.isCancelled { throw .cancelled }
      let data: Data
      if let text = documents[path] {
        data = Data(text.utf8)
      } else {
        data = try read(root.appending(path: path))
      }
      try writing { () throws(ZipError) in try writer.add(path, data: data) }
    }
    try writing { () throws(ZipError) in try writer.finish() }
  }

  private static func writing<T>(_ step: () throws(ZipError) -> T) throws(SendFailure) -> T {
    do {
      return try step()
    } catch {
      switch error {
      case .tooLarge: throw .invalidBook("It's too large to package as an EPUB")
      case .cannotWrite(let reason): throw .localStorage(reason)
      }
    }
  }

  private static func read(_ url: URL) throws(SendFailure) -> Data {
    do {
      return try Data(contentsOf: url)
    } catch {
      throw .invalidBook(error.localizedDescription)
    }
  }
}
