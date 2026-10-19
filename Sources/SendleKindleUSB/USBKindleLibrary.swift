import Foundation
import SendleDomain

/// Lists the books on a drive-mounted Kindle without changing it.
public struct USBKindleLibrary: KindleLibrary {
  package typealias DeviceKey = @Sendable (KindleVolume) -> String
  package typealias FreeSpace = @Sendable (URL) -> Int64?

  private let cacheDirectory: URL
  private let deviceKey: DeviceKey
  private let freeSpace: FreeSpace
  private let log: any ActivityLog

  public init(cacheDirectory: URL, log: any ActivityLog = NoActivityLog()) {
    self.init(
      cacheDirectory: cacheDirectory, deviceKey: { $0.name }, freeSpace: Self.availableCapacity,
      log: log)
  }

  package init(
    cacheDirectory: URL,
    deviceKey: @escaping DeviceKey,
    freeSpace: @escaping FreeSpace,
    log: any ActivityLog
  ) {
    self.cacheDirectory = cacheDirectory
    self.deviceKey = deviceKey
    self.freeSpace = freeSpace
    self.log = log
  }

  public func listing(
    of volume: KindleVolume,
    progress: @escaping @Sendable (_ done: Int, _ total: Int) async -> Void
  ) async throws(KindleListingError) -> KindleListing {
    let clock = ContinuousClock()
    let start = clock.now
    let documents = volume.mountURL.appending(path: "documents", directoryHint: .isDirectory)
    guard Self.isFolder(documents) else { throw .deviceDisconnected }
    let files = Self.files(under: documents)
    let calibreLibrary = FileManager.default.fileExists(
      atPath: volume.mountURL.appending(path: "metadata.calibre").path)
    await progress(0, files.count)
    var books: [KindleBook] = []
    for (index, file) in files.enumerated() {
      if Task.isCancelled { throw .cancelled }
      guard Self.isFolder(documents) else { throw .deviceDisconnected }
      books.append(
        KindleBookReader.read(
          file.url, relativePath: file.relativePath, size: file.size, modified: file.modified,
          calibreLibrary: calibreLibrary))
      await progress(index + 1, files.count)
    }
    guard Self.isFolder(documents) else { throw .deviceDisconnected }
    log.info(
      .usb,
      "Read \(volume.name): \(books.count) books in \(Elapsed.text(clock.now - start))")
    return KindleListing(books: books, freeBytes: freeSpace(volume.mountURL))
  }

  public func cover(of book: KindleBook, on volume: KindleVolume, maxPixel: Int) async -> Cover {
    .none
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
  /// ".sdr" (a book's sidecar) is not a book, nor is anything inside it.
  private static func files(under documents: URL) -> [File] {
    guard
      let walker = FileManager.default.enumerator(
        at: documents, includingPropertiesForKeys: keys, options: [],
        errorHandler: { _, _ in true })
    else { return [] }
    let rootComponents = documents.resolvingSymlinksInPath().pathComponents.count
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
      let relative = url.resolvingSymlinksInPath().pathComponents.dropFirst(rootComponents)
      files.append(
        File(
          url: url, relativePath: relative.joined(separator: "/"),
          size: Int64(values?.fileSize ?? 0),
          modified: values?.contentModificationDate ?? .distantPast))
    }
    return files.sorted { $0.relativePath < $1.relativePath }
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
