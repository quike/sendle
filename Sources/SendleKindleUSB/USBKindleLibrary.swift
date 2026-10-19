import Foundation
import SendleDomain

/// Lists the books on a drive-mounted Kindle without changing it.
public struct USBKindleLibrary: KindleLibrary {
  package typealias DeviceKey = @Sendable (KindleVolume) -> String
  package typealias FreeSpace = @Sendable (URL) -> Int64?

  private let cache: KindleListingCache
  private let deviceKey: DeviceKey
  private let freeSpace: FreeSpace
  private let log: any ActivityLog

  public init(cacheDirectory: URL, log: any ActivityLog = NoActivityLog()) {
    self.init(
      cacheDirectory: cacheDirectory, deviceKey: Self.deviceKey(of:),
      freeSpace: Self.availableCapacity, log: log)
  }

  package init(
    cacheDirectory: URL,
    deviceKey: @escaping DeviceKey,
    freeSpace: @escaping FreeSpace,
    log: any ActivityLog
  ) {
    cache = KindleListingCache(directory: cacheDirectory)
    self.deviceKey = deviceKey
    self.freeSpace = freeSpace
    self.log = log
  }

  /// A Kindle is its volume's UUID, or its name when the volume has none.
  package static func deviceKey(uuid: String?, name: String) -> String {
    uuid ?? name
  }

  package static func deviceKey(of volume: KindleVolume) -> String {
    let uuid = try? volume.mountURL.resourceValues(forKeys: [.volumeUUIDStringKey])
    return deviceKey(uuid: uuid?.volumeUUIDString, name: volume.name)
  }

  public func listing(
    of volume: KindleVolume,
    progress: @escaping @Sendable (_ done: Int, _ total: Int) async -> Void
  ) async throws(KindleListingError) -> KindleListing {
    let clock = ContinuousClock()
    let start = clock.now
    let documents = volume.mountURL.appending(path: "documents", directoryHint: .isDirectory)
    guard Self.isFolder(documents) else { throw .deviceDisconnected }
    let files = try Self.files(under: documents)
    let calibreLibrary = FileManager.default.fileExists(
      atPath: volume.mountURL.appending(path: "metadata.calibre").path)
    let device = deviceKey(volume)
    let cached = cache.load(device: device)
    var reused = 0
    await progress(0, files.count)
    var books: [KindleBook] = []
    var cacheable: [KindleBook] = []
    for (index, file) in files.enumerated() {
      if Task.isCancelled { throw .cancelled }
      guard Self.isFolder(documents) else { throw .deviceDisconnected }
      if let book = cached[file.relativePath], book.byteCount == file.size,
        book.modified == file.modified
      {
        let book = book.withSource(
          KindleBookSource.detect(
            relativePath: book.id.relativePath, asin: book.asin, calibreLibrary: calibreLibrary))
        books.append(book)
        cacheable.append(book)
        reused += 1
      } else {
        let reading = KindleBookReader.read(
          file.url, relativePath: file.relativePath, size: file.size, modified: file.modified,
          calibreLibrary: calibreLibrary)
        books.append(reading.book)
        if reading.readHeaders { cacheable.append(reading.book) }
      }
      await progress(index + 1, files.count)
    }
    guard Self.isFolder(documents) else { throw .deviceDisconnected }
    cache.save(cacheable, device: device)
    log.info(
      .usb,
      "Read \(volume.name) (device \(device)): \(books.count) books, "
        + "\(books.count - reused) read and \(reused) from the cache, "
        + "in \(Elapsed.text(clock.now - start))")
    return KindleListing(books: books, freeBytes: freeSpace(volume.mountURL))
  }

  public func cover(of book: KindleBook, on volume: KindleVolume, maxPixel: Int) async -> Cover {
    KindleCovers.cover(of: book, onKindleAt: volume.mountURL, maxPixel: maxPixel)
  }

  private struct File {
    let url: URL
    let relativePath: String
    let size: Int64
    let modified: Date
  }

  private static let keys: [URLResourceKey] = [
    .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey,
    .contentModificationDateKey,
  ]

  /// The books under `documents`, in path order. A name starting with "." or a folder ending
  /// ".sdr" (a book's sidecar) is not a book, nor is anything inside it. A folder that can't be
  /// read fails the listing, since a partial one would pass for a Kindle without those books.
  private static func files(under documents: URL) throws(KindleListingError) -> [File] {
    let failure = FirstError()
    guard
      let walker = FileManager.default.enumerator(
        at: documents, includingPropertiesForKeys: keys, options: [],
        errorHandler: { _, error in
          failure.record(error)
          return false
        })
    else { throw .unreadable(documents.lastPathComponent) }
    let prefix = documents.path + "/"
    var files: [File] = []
    while let url = walker.nextObject() as? URL {
      let name = url.lastPathComponent
      let values = try? url.resourceValues(forKeys: Set(keys))
      if name.hasPrefix(".") || (values?.isDirectory == true && name.hasSuffix(".sdr")) {
        walker.skipDescendants()
        continue
      }
      guard values?.isRegularFile == true, values?.isSymbolicLink != true,
        name.caseInsensitiveCompare("My Clippings.txt") != .orderedSame,
        KindleBookReader.formats.contains(url.pathExtension.lowercased())
      else { continue }
      files.append(
        File(
          url: url, relativePath: relativePath(of: url, under: documents, prefix: prefix),
          size: Int64(values?.fileSize ?? 0),
          modified: values?.contentModificationDate ?? .distantPast))
    }
    if let error = failure.error {
      throw isFolder(documents) ? .unreadable(error.localizedDescription) : .deviceDisconnected
    }
    return files.sorted { $0.relativePath < $1.relativePath }
  }

  /// The enumerator hands back paths under the URL it was given, unless it resolved a link on the way.
  private static func relativePath(of url: URL, under documents: URL, prefix: String) -> String {
    if url.path.hasPrefix(prefix) { return String(url.path.dropFirst(prefix.count)) }
    let root = documents.resolvingSymlinksInPath().pathComponents.count
    return url.resolvingSymlinksInPath().pathComponents.dropFirst(root).joined(separator: "/")
  }

  private final class FirstError: @unchecked Sendable {
    private let lock = NSLock()
    private var first: (any Error)?

    var error: (any Error)? { lock.withLock { first } }

    func record(_ error: any Error) {
      lock.withLock { first = first ?? error }
    }
  }

  private static func isFolder(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func availableCapacity(_ mount: URL) -> Int64? {
    (try? mount.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?
      .volumeAvailableCapacity.map(Int64.init)
  }
}
