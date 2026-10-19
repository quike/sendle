import Darwin
import Foundation

/// Bytes read from the front of a book without loading all of it.
package protocol ByteSource {
  var count: Int { get }
  /// Nil when any of `range` lies outside the source or can't be read.
  func bytes(_ range: Range<Int>) -> [UInt8]?
}

package struct DataBytes: ByteSource {
  private let data: Data

  package init(_ data: Data) {
    self.data = data
  }

  package var count: Int { data.count }

  package func bytes(_ range: Range<Int>) -> [UInt8]? {
    guard range.lowerBound >= 0, range.upperBound <= data.count else { return nil }
    let start = data.startIndex
    return [UInt8](data[(start + range.lowerBound)..<(start + range.upperBound)])
  }
}

/// A regular file read in pieces with `pread`, counting what it read.
package final class FileBytes: ByteSource {
  package let count: Int
  package private(set) var bytesRead = 0
  private let descriptor: Int32

  package init?(url: URL) {
    let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else { return nil }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
      close(descriptor)
      return nil
    }
    self.descriptor = descriptor
    count = Int(info.st_size)
  }

  deinit { close(descriptor) }

  package func bytes(_ range: Range<Int>) -> [UInt8]? {
    guard range.lowerBound >= 0, range.upperBound <= count else { return nil }
    var buffer = [UInt8](repeating: 0, count: range.count)
    var done = 0
    while done < buffer.count {
      let read = buffer[done...].withUnsafeMutableBytes {
        pread(descriptor, $0.baseAddress, $0.count, off_t(range.lowerBound + done))
      }
      if read < 0 && errno == EINTR { continue }
      guard read > 0 else { return nil }
      done += read
    }
    bytesRead += done
    return buffer
  }
}

/// Where a MOBI-family book keeps its record 0, its EXTH entries and its cover (MobileRead's MOBI
/// page). Every offset is checked against the source, so a damaged or truncated book reads as nil.
package struct MobiLayout {
  /// Record 0 is read whole up to this size.
  static let maxRecordZero = 1 << 20
  static let coverEntry: UInt32 = 201

  package let record0Start: Int
  package let record0: [UInt8]
  /// The file offsets of each EXTH entry's value, by kind.
  package private(set) var entries: [UInt32: [Range<Int>]] = [:]
  package private(set) var cover: Range<Int>?

  package init?(_ source: some ByteSource) {
    guard source.count >= 78, let head = source.bytes(0..<78),
      head[60..<68].elementsEqual("BOOKMOBI".utf8),
      let count = head.uint16(at: 76).map(Int.init), count > 0,
      let table = source.bytes(78..<(78 + 8 * count))
    else { return nil }
    var starts: [Int] = []
    for index in 0..<count {
      guard let start = table.uint32(at: 8 * index).map(Int.init), start <= source.count
      else { return nil }
      starts.append(start)
    }
    func record(_ index: Int) -> Range<Int>? {
      guard index >= 0, index < count else { return nil }
      let end = index + 1 < count ? starts[index + 1] : source.count
      return starts[index] <= end ? starts[index]..<end : nil
    }
    guard let first = record(0), first.count >= 24,
      let record0 = source.bytes(
        first.lowerBound..<(first.lowerBound + min(first.count, Self.maxRecordZero))),
      record0[16..<20].elementsEqual("MOBI".utf8),
      let mobiLength = record0.uint32(at: 20).map(Int.init)
    else { return nil }
    var position = 16 + mobiLength
    guard position + 12 <= record0.count,
      record0[position..<(position + 4)].elementsEqual("EXTH".utf8),
      let entryCount = record0.uint32(at: position + 8)
    else { return nil }
    position += 12
    for _ in 0..<entryCount {
      guard let kind = record0.uint32(at: position),
        let length = record0.uint32(at: position + 4).map(Int.init), length >= 8,
        position + length <= record0.count
      else { return nil }
      let value = (first.lowerBound + position + 8)..<(first.lowerBound + position + length)
      entries[kind, default: []].append(value)
      position += length
    }
    record0Start = first.lowerBound
    self.record0 = record0
    if let firstImage = record0.uint32(at: 0x6C), firstImage != .max,
      let value = entries[Self.coverEntry]?.last, value.count >= 4,
      let offset = record0.uint32(at: value.lowerBound - first.lowerBound), offset != .max
    {
      cover = record(Int(firstImage) + Int(offset))
    }
  }

  /// Where `kind`'s value sits. Of a repeated entry, the last one.
  package func range(of kind: UInt32) -> Range<Int>? {
    entries[kind]?.last
  }
}

extension [UInt8] {
  func uint16(at offset: Int) -> UInt16? {
    guard offset >= 0, offset + 2 <= count else { return nil }
    return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
  }

  func uint32(at offset: Int) -> UInt32? {
    guard offset >= 0, offset + 4 <= count else { return nil }
    return self[offset..<(offset + 4)].reduce(0) { $0 << 8 | UInt32($1) }
  }
}
