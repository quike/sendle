import Darwin
import Foundation
import SendleDomain
import os

/// Hashes the books on a Kindle, keeping each digest beside the Kindle's listing cache while the
/// book keeps its size and date, so a match doesn't read every PDF over USB again.
public struct CachedKindleDigester: KindleDigester {
  private let cache: KindleListingCache
  private let deviceKey: USBKindleLibrary.DeviceKey
  private let digester: any FileDigester
  /// Each Kindle's digests by relative path, once read from the cache.
  private let known = OSAllocatedUnfairLock<[String: [String: KindleListingCache.Digest]]>(
    initialState: [:])

  public init(cacheDirectory: URL) {
    self.init(
      cacheDirectory: cacheDirectory, deviceKey: USBKindleLibrary.deviceKey(of:),
      digester: SHA256FileDigester())
  }

  package init(
    cacheDirectory: URL, deviceKey: @escaping USBKindleLibrary.DeviceKey,
    digester: any FileDigester
  ) {
    cache = KindleListingCache(directory: cacheDirectory)
    self.deviceKey = deviceKey
    self.digester = digester
  }

  public func sha256(of book: KindleBook, on volume: KindleVolume) async -> String? {
    let device = deviceKey(volume)
    let path = book.id.relativePath
    if let sha256 = digests(of: device)[path]?.sha256(of: book) { return sha256 }
    guard let sha256 = await digester.sha256(of: book.url(on: volume)) else { return nil }
    known.withLock { known in
      known[device, default: [:]][path] = KindleListingCache.Digest(of: book, sha256: sha256)
      cache.saveDigests(known[device] ?? [:], device: device)
    }
    return sha256
  }

  private func digests(of device: String) -> [String: KindleListingCache.Digest] {
    known.withLock { known in
      if let loaded = known[device] { return loaded }
      let loaded = cache.loadDigests(device: device)
      known[device] = loaded
      return loaded
    }
  }
}

/// Remembers the digest of each file on this Mac while it keeps its size and modification date.
public struct CachedFileDigester: FileDigester {
  private struct Entry {
    let size: Int64
    let modified: Date
    let sha256: String
  }

  private let digester: any FileDigester
  private let known = OSAllocatedUnfairLock<[String: Entry]>(initialState: [:])

  public init(_ digester: any FileDigester = SHA256FileDigester()) {
    self.digester = digester
  }

  public func sha256(of file: URL) async -> String? {
    guard let (size, modified) = Self.stamp(of: file) else { return nil }
    if let entry = known.withLock({ $0[file.path] }), entry.size == size,
      entry.modified == modified
    {
      return entry.sha256
    }
    guard let sha256 = await digester.sha256(of: file) else { return nil }
    known.withLock { $0[file.path] = Entry(size: size, modified: modified, sha256: sha256) }
    return sha256
  }

  /// Read with stat, since a URL keeps the resource values it read first.
  private static func stamp(of file: URL) -> (Int64, Date)? {
    var info = stat()
    guard stat(file.path, &info) == 0 else { return nil }
    let time = info.st_mtimespec
    return (
      Int64(info.st_size),
      Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000)
    )
  }
}
