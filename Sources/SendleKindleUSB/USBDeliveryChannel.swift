import Darwin
import Foundation
import SendleDomain

/// Copies a book into a drive-mounted Kindle's `documents` folder. The copy is written under a
/// hidden name and renamed when complete, so the Kindle never lists half a book.
public struct USBDeliveryChannel: DeliveryChannel {
  package typealias FreeSpace = @Sendable (URL) -> Int64?

  private let volume: KindleVolume
  private let chunkSize: Int
  private let freeSpace: FreeSpace

  public init(volume: KindleVolume) {
    self.init(volume: volume, chunkSize: 1 << 20, freeSpace: Self.availableCapacity)
  }

  package init(volume: KindleVolume, chunkSize: Int, freeSpace: @escaping FreeSpace) {
    self.volume = volume
    self.chunkSize = chunkSize
    self.freeSpace = freeSpace
  }

  public func deliver(
    _ file: PreparedFile,
    named baseName: String,
    progress: @Sendable (Double) async -> Void
  ) async throws(SendFailure) {
    let documents = volume.mountURL.appending(path: "documents", directoryHint: .isDirectory)
    guard Self.isFolder(documents) else { throw .deviceDisconnected }
    Self.removeLeftovers(in: documents)
    let size = try Self.size(of: file.url)
    if let free = freeSpace(volume.mountURL), free < size { throw .diskFull }
    let partial = documents.appending(path: ".sendle-\(UUID().uuidString).partial")
    let destination = documents.appending(path: "\(baseName).\(file.format.fileExtension)")
    do throws(SendFailure) {
      try await copy(file.url, size: size, to: partial, in: documents, progress: progress)
      guard rename(partial.path, destination.path) == 0 else {
        throw Self.failure(errno: errno, volumeIsMounted: Self.isFolder(documents))
      }
    } catch {
      unlink(partial.path)
      throw error
    }
  }

  /// What a failed write to the Kindle means. Once its `documents` folder is gone, the Kindle was
  /// unplugged or ejected, whatever the error says.
  package static func failure(errno code: Int32, volumeIsMounted: Bool) -> SendFailure {
    guard volumeIsMounted else { return .deviceDisconnected }
    switch code {
    case ENOSPC, EDQUOT: return .diskFull
    case EIO, ENXIO, ENODEV: return .deviceDisconnected
    default: return .copyFailed(String(cString: strerror(code)))
    }
  }

  // MARK: Private

  private func copy(
    _ source: URL,
    size: Int64,
    to partial: URL,
    in documents: URL,
    progress: @Sendable (Double) async -> Void
  ) async throws(SendFailure) {
    let input = open(source.path, O_RDONLY)
    guard input >= 0 else { throw Self.readFailure(errno) }
    defer { close(input) }
    let output = open(partial.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
    guard output >= 0 else { throw writeFailure(errno, documents) }
    var isOpen = true
    defer { if isOpen { close(output) } }

    var buffer = [UInt8](repeating: 0, count: chunkSize)
    var copied: Int64 = 0
    var reported = -1
    while true {
      if Task.isCancelled { throw .cancelled }
      let count = Self.retrying { read(input, &buffer, chunkSize) }
      guard count >= 0 else { throw Self.readFailure(errno) }
      if count == 0 { break }
      try writeAll(buffer[..<count], to: output, in: documents)
      copied += Int64(count)
      // About a hundred updates, however large the book.
      let percent = size > 0 ? Int(copied * 100 / size) : 100
      if percent != reported {
        reported = percent
        await progress(size > 0 ? min(Double(copied) / Double(size), 1) : 1)
      }
    }
    guard fsync(output) == 0 else { throw writeFailure(errno, documents) }
    isOpen = false
    guard close(output) == 0 else { throw writeFailure(errno, documents) }
  }

  private func writeAll(
    _ bytes: ArraySlice<UInt8>,
    to output: Int32,
    in documents: URL
  ) throws(SendFailure) {
    var offset = bytes.startIndex
    while offset < bytes.endIndex {
      let written = bytes[offset...].withUnsafeBytes { chunk in
        Self.retrying { write(output, chunk.baseAddress, chunk.count) }
      }
      guard written > 0 else { throw writeFailure(errno, documents) }
      offset += written
    }
  }

  private func writeFailure(_ code: Int32, _ documents: URL) -> SendFailure {
    Self.failure(errno: code, volumeIsMounted: Self.isFolder(documents))
  }

  private static func readFailure(_ code: Int32) -> SendFailure {
    code == ENOENT
      ? .missing
      : .copyFailed(
        "Sendle couldn't read the book on this Mac (\(String(cString: strerror(code)))).")
  }

  private static func size(of file: URL) throws(SendFailure) -> Int64 {
    var info = stat()
    guard stat(file.path, &info) == 0 else { throw readFailure(errno) }
    return Int64(info.st_size)
  }

  private static func isFolder(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  /// A copy cut short by a quit or a crash leaves a hidden partial file behind.
  private static func removeLeftovers(in documents: URL) {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
    for name in names where name.hasPrefix(".sendle-") && name.hasSuffix(".partial") {
      unlink(documents.appending(path: name).path)
    }
  }

  private static func retrying(_ call: () -> Int) -> Int {
    var result: Int
    repeat { result = call() } while result < 0 && errno == EINTR
    return result
  }

  private static func availableCapacity(_ volume: URL) -> Int64? {
    let values = try? volume.resourceValues(forKeys: [.volumeAvailableCapacityKey])
    return values?.volumeAvailableCapacity.map(Int64.init)
  }
}
