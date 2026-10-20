import Foundation
import SendleDomain

/// Packages a book as an EPUB Amazon accepts: `mimetype` first and stored, Apple's additions left
/// out, the details a send carries written into the package document, and the Kindle fixes
/// applied. Books' own files are only read.
public struct KindleEPUBPreparer: EPUBPreparer {
  private let extractor: any ArchiveExtractor = DittoExtractor()
  private let log: any ActivityLog

  /// The package documents after the details pass, and what it wrote.
  private struct Written {
    var texts: [String: String]
    var package: EPUBPackage
    var applied: [PackageDetail] = []
    var cover: (path: String, data: Data)?
  }

  public init(log: any ActivityLog = NoActivityLog()) {
    self.log = log
  }

  public func prepare(_ book: Book, details: PackageDetails, in staging: URL)
    async throws(SendFailure) -> PreparedFile
  {
    let root = try source(of: book, in: staging)
    if EPUBProtectionInspector.hasDRMEvidence(in: root) { throw .protected }
    guard let original = OPFReader.package(inEPUBAt: root) else {
      throw .invalidBook("Its package document is missing or unreadable")
    }
    let entries = EPUBContents.entries(in: root)
    let texts = Self.texts(of: KindleFixer.markupPaths(in: original), in: root, among: entries)
    let written = writeDetails(details, into: texts, package: original)
    let fixed = KindleFixer(language: book.language).apply(
      to: written.texts, package: written.package)

    var replacements: [String: Data] = [:]
    for (path, text) in written.texts.merging(fixed.documents, uniquingKeysWith: { $1 })
    where text != texts[path] {
      replacements[path] = Data(text.utf8)
    }
    if let cover = written.cover { replacements[cover.path] = cover.data }
    let output = staging.appending(path: FileNaming.baseName(for: book) + ".epub")
    try Self.zip(entries, from: root, replacing: replacements, to: output)
    return PreparedFile(
      url: output, format: .epub, fixes: fixed.fixes, applied: written.applied,
      edition: original.edition)
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

  /// `texts` with `details` written into the package document, and the package read again from
  /// it. A package that can't be edited is left as it is, and the book goes out without the
  /// details.
  private func writeDetails(
    _ details: PackageDetails, into texts: [String: String], package: EPUBPackage
  ) -> Written {
    let unchanged = Written(texts: texts, package: package)
    guard !details.isEmpty else { return unchanged }
    guard let text = texts[package.path],
      let result = PackageDetailsEditor.apply(
        details, to: text, at: package.path, package: package, coverImage: coverImage(of: details)),
      let edited = OPFReader.package(Data(result.text.utf8), at: package.path)
    else {
      log.warning(
        .epub,
        "Couldn't write the details into the book (its package document can't be edited); "
          + "sending it as it is")
      return unchanged
    }
    var written = Written(
      texts: texts, package: edited, applied: result.applied, cover: result.coverFile)
    written.texts[package.path] = result.text
    return written
  }

  /// The stored image for the book's new cover. Nil without one, or when it can't be read, which
  /// leaves the book's own cover.
  private func coverImage(of details: PackageDetails) -> Data? {
    guard let url = details.cover else { return nil }
    do {
      return try Data(contentsOf: url)
    } catch {
      log.warning(
        .epub,
        "Couldn't read the new cover (\(error.localizedDescription)); "
          + "sending the book with its own")
      return nil
    }
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

  /// Writes `entries` from `root`, with the bytes in `replacements` in place of a file's own. A
  /// replacement for a path that isn't among the entries is added after them.
  private static func zip(
    _ entries: [String],
    from root: URL,
    replacing replacements: [String: Data],
    to output: URL
  ) throws(SendFailure) {
    let writer = try writing { () throws(ZipError) in try ZipWriter(creatingFileAt: output) }
    try writing { () throws(ZipError) in
      try writer.add("mimetype", data: Data("application/epub+zip".utf8), method: .stored)
    }
    let existing = Set(entries)
    let added = replacements.keys.filter { !existing.contains($0) }.sorted()
    for path in entries + added {
      if Task.isCancelled { throw .cancelled }
      let data: Data
      if let replacement = replacements[path] {
        data = replacement
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
