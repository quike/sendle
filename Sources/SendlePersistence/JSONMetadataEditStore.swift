import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SendleDomain
import UniformTypeIdentifiers

public actor JSONMetadataEditStore: MetadataEditStore {
  nonisolated public let coverFolder: URL

  private struct File: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var books: [BookID: BookEdit]
    var writers: [WriterKey: WriterEdit]

    init(_ edits: MetadataEdits) {
      books = edits.books
      writers = edits.writers
    }

    var isFromANewerVersion: Bool { version > Self.currentVersion }

    /// A cover name that isn't a file in the cover folder is ignored, so the store never reads or
    /// deletes anything else.
    var edits: MetadataEdits {
      var books = books
      for (id, edit) in books {
        if let cover = edit.cover, !Self.isFileName(cover) { books[id]?.cover = nil }
      }
      return MetadataEdits(books: books, writers: writers)
    }

    private static func isFileName(_ name: String) -> Bool {
      !name.isEmpty && name != "." && name != ".."
        && URL(filePath: name).lastPathComponent == name
    }
  }

  private let file: JSONFile<File>
  private let log: any ActivityLog
  private var sweptUnusedCovers = false

  public init(directory: URL, log: any ActivityLog = NoActivityLog()) {
    file = JSONFile(url: directory.appending(path: "edits.json"), log: log)
    coverFolder = directory.appending(path: "edit-covers", directoryHint: .isDirectory)
    self.log = log
  }

  /// The first call after launch also deletes cover files no edit refers to, unless the file is
  /// from a newer version, which may name them in a way this one can't read.
  public func edits() -> MetadataEdits {
    let stored = load()
    let edits = stored.edits
    if !sweptUnusedCovers {
      sweptUnusedCovers = true
      if !stored.isFromANewerVersion {
        deleteCovers(coverFileNames().subtracting(coverNames(in: edits)))
      }
    }
    return edits
  }

  public func update(
    book: BookID, cover: CoverChange, _ change: @Sendable (inout MetadataEdits) -> Void
  ) throws(MetadataEditError) {
    let stored = load()
    // Rewriting a newer file as this version would drop what this version can't read.
    guard !stored.isFromANewerVersion else {
      log.error(.app, "Couldn't save edits.json: it is from a newer version of Sendle")
      throw .storage(.writeFailed("edits.json is from a newer version of Sendle"))
    }
    let previous = stored.edits
    var updated = previous
    change(&updated)

    var created: URL?
    if case .replace(let data) = cover {
      let image = try CoverImage.jpeg(from: data)
      let name = "\(Self.fileName(for: book))-\(image.digest).jpg"
      created = try writeCover(image.data, named: name)
      updated.books[book, default: BookEdit()].cover = name
    } else if case .revert = cover {
      updated.books[book]?.cover = nil
    }

    do {
      try file.write(File(updated))
    } catch {
      if let created { try? FileManager.default.removeItem(at: created) }
      throw .storage(error)
    }
    deleteCovers(coverNames(in: previous).subtracting(coverNames(in: updated)))
  }

  private func load() -> File {
    // An unreadable file may still name covers, so none are swept before the next launch.
    file.read(quarantiningCorruptAt: Date()) { _ in sweptUnusedCovers = true } ?? File(.none)
  }

  /// The file's URL when this call created it.
  private func writeCover(_ data: Data, named name: String) throws(MetadataEditError) -> URL? {
    let url = coverFolder.appending(path: name)
    let existed = FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    do {
      try FileManager.default.createDirectory(at: coverFolder, withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
    } catch {
      log.error(.app, "Couldn't save the cover \(name): \(error.localizedDescription)")
      throw .storage(.writeFailed(error.localizedDescription))
    }
    return existed ? nil : url
  }

  private func coverNames(in edits: MetadataEdits) -> Set<String> {
    Set(edits.books.values.compactMap(\.cover))
  }

  private func coverFileNames() -> Set<String> {
    Set(
      (try? FileManager.default.contentsOfDirectory(atPath: coverFolder.path(percentEncoded: false)))
        ?? [])
  }

  private func deleteCovers(_ names: Set<String>) {
    for name in names {
      try? FileManager.default.removeItem(at: coverFolder.appending(path: name))
    }
  }

  /// Book IDs are Books' own strings; percent-encoding keeps them distinct and path-safe.
  private static func fileName(for id: BookID) -> String {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    return id.rawValue.addingPercentEncoding(withAllowedCharacters: safe) ?? "book"
  }
}

private enum CoverImage {
  static let maxBytes = 20_000_000
  static let maxPixels = 2560
  static let quality = 0.9

  /// The image re-encoded as a JPEG, and the first 12 hex digits of its SHA-256.
  static func jpeg(from data: Data) throws(MetadataEditError) -> (data: Data, digest: String) {
    guard data.count <= maxBytes else { throw .imageTooLarge }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = scaled(source),
      let jpeg = encode(image)
    else { throw .unreadableImage }
    let digest = SHA256.hash(data: jpeg).prefix(6).map { String(format: "%02x", $0) }.joined()
    return (jpeg, digest)
  }

  private static func scaled(_ source: CGImageSource) -> CGImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  private static func encode(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: quality,
      kCGImageDestinationBackgroundColor: CGColor(gray: 1, alpha: 1),
    ]
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}
