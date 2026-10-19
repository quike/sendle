import CryptoKit
import Foundation
import SendleDomain

/// Hashes a file in 1 MiB pieces, so a large book is never held whole.
public struct SHA256FileDigester: FileDigester {
  private static let chunkSize = 1 << 20

  public init() {}

  public func sha256(of file: URL) async -> String? {
    guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
    defer { try? handle.close() }
    var hash = SHA256()
    do {
      while !Task.isCancelled, let chunk = try handle.read(upToCount: Self.chunkSize),
        !chunk.isEmpty
      {
        hash.update(data: chunk)
      }
    } catch {
      return nil
    }
    return Task.isCancelled ? nil : hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
