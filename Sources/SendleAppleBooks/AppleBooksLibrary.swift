import Foundation
import SendleDomain

/// The books in Apple Books' own library, read without ever writing to it.
public struct AppleBooksLibrary: BooksLibrary {
  private let location: LibraryLocation
  private let probe: any FileProbe
  private let reader: LibraryReader
  private let batchDelay: DispatchTimeInterval

  public init(location: LibraryLocation = .standard()) {
    self.init(location: location, probe: DatalessAwareFileProbe())
  }

  package init(
    location: LibraryLocation,
    probe: any FileProbe,
    scratchDirectory: URL = FileManager.default.temporaryDirectory,
    batchDelay: DispatchTimeInterval = .seconds(1)
  ) {
    self.location = location
    self.probe = probe
    reader = LibraryReader(scratchDirectory: scratchDirectory)
    self.batchDelay = batchDelay
  }

  public func books() async throws(LibraryError) -> [Book] {
    try reader.records(in: location.databaseURL()).compactMap(book)
  }

  public func changes() -> AsyncStream<Void> {
    let (stream, continuation) = AsyncStream.makeStream(
      of: Void.self, bufferingPolicy: .bufferingNewest(1))
    let watched = location.watched
    let watcher = LibraryWatcher(
      directory: watched.directory, isLibraryFile: watched.isLibraryFile, batchDelay: batchDelay
    ) {
      continuation.yield()
    }
    guard watcher.start() else {
      continuation.finish()
      return stream
    }
    continuation.onTermination = { _ in watcher.stop() }
    return stream
  }

  private func book(from record: AssetRecord) -> Book? {
    let path = NSString(string: record.path).expandingTildeInPath
    guard path.hasPrefix("/") else { return nil }
    let url = URL(filePath: path)
    guard let format = Self.format(of: record, at: url) else { return nil }
    let status = probe.status(of: url)
    return Book(
      id: BookID(rawValue: record.assetID),
      title: Self.nonEmpty(record.title) ?? url.deletingPathExtension().lastPathComponent,
      author: Self.nonEmpty(record.author),
      language: Self.nonEmpty(record.language),
      format: format,
      fileURL: url,
      sizeBytes: Self.size(status, record),
      addedAt: record.creationDate.map(Date.init(timeIntervalSinceReferenceDate:)) ?? .distantPast,
      isStorePurchase: Self.nonEmpty(record.storeID) != nil,
      availability: Self.availability(status, record)
    )
  }

  private static func format(of record: AssetRecord, at url: URL) -> BookFormat? {
    switch record.contentType {
    case 1: .epub
    case 3: .pdf
    default: BookFormat(rawValue: url.pathExtension.lowercased())
    }
  }

  private static func availability(_ status: FileStatus?, _ record: AssetRecord) -> Availability {
    if record.state == 3 { return .inCloudOnly }
    guard let status else { return .missing }
    return status.isDataless ? .inCloudOnly : .ready
  }

  /// A file's own size; an unzipped EPUB folder relies on Books' figure, which is often 0.
  private static func size(_ status: FileStatus?, _ record: AssetRecord) -> Int64? {
    if let status, !status.isDirectory { return status.size }
    return record.fileSize.flatMap { $0 > 0 ? $0 : nil }
  }

  private static func nonEmpty(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    return trimmed
  }
}
