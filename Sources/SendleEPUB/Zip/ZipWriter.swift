import Foundation

package enum ZipError: Error, Hashable, Sendable {
  /// Past a limit of the classic ZIP format (4 GB, 65,534 entries). EPUBs never get there.
  case tooLarge
  case cannotWrite(String)
}

/// Writes a ZIP archive entry by entry: each local header and its data, then the central
/// directory. No extra fields, no data descriptors and no ZIP64.
package final class ZipWriter {
  package enum Method: UInt16, Sendable {
    case stored = 0
    case deflated = 8
  }

  private let handle: FileHandle
  private let time: UInt16
  private let date: UInt16
  private var offset = 0
  private var centralDirectory = Data()
  private var count = 0

  package init(creatingFileAt url: URL, modified: Date = Date()) throws(ZipError) {
    guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil),
      let handle = try? FileHandle(forWritingTo: url)
    else { throw .cannotWrite("Couldn't create the archive file") }
    self.handle = handle
    (time, date) = Self.dosTimestamp(modified)
  }

  /// Adds a file. A deflated entry that wouldn't shrink is stored instead.
  package func add(_ name: String, data: Data, method requested: Method = .deflated)
    throws(ZipError)
  {
    guard count < 0xFFFE, name.utf8.count <= 0xFFFF else { throw .tooLarge }
    var method = Method.stored
    var payload = data
    if requested == .deflated, let deflated = try? (data as NSData).compressed(using: .zlib),
      deflated.length < data.count
    {
      method = .deflated
      payload = deflated as Data
    }
    let nameBytes = Data(name.utf8)
    let fields = EntryFields(
      version: method == .deflated ? 20 : 10,
      flags: name.utf8.allSatisfy { $0 < 0x80 } ? 0 : 0x0800,  // bit 11: the name is UTF-8
      method: method.rawValue,
      crc: CRC32.checksum(data),
      compressedSize: try Self.field32(payload.count),
      size: try Self.field32(data.count),
      nameLength: UInt16(nameBytes.count)
    )
    let headerOffset = try Self.field32(offset)

    var local = Data()
    local.append32(0x0403_4B50)
    append(fields, to: &local)
    local.append16(0)  // extra field length
    local.append(nameBytes)
    try write(local)
    try write(payload)

    centralDirectory.append32(0x0201_4B50)
    centralDirectory.append16(0x0314)  // made by Unix, ZIP 2.0
    append(fields, to: &centralDirectory)
    centralDirectory.append16(0)  // extra field length
    centralDirectory.append16(0)  // comment length
    centralDirectory.append16(0)  // disk number
    centralDirectory.append16(0)  // internal attributes
    centralDirectory.append32(UInt32(0o100644) << 16)  // regular file, rw-r--r--
    centralDirectory.append32(headerOffset)
    centralDirectory.append(nameBytes)

    offset += local.count + payload.count
    count += 1
  }

  /// Writes the central directory and closes the file.
  package func finish() throws(ZipError) {
    var end = Data()
    end.append32(0x0605_4B50)
    end.append16(0)  // this disk
    end.append16(0)  // disk holding the directory
    end.append16(UInt16(count))
    end.append16(UInt16(count))
    end.append32(try Self.field32(centralDirectory.count))
    end.append32(try Self.field32(offset))
    end.append16(0)  // comment length
    try write(centralDirectory)
    try write(end)
    do {
      try handle.close()
    } catch {
      throw .cannotWrite(error.localizedDescription)
    }
  }

  /// A 32-bit header field. `0xFFFFFFFF` is reserved for ZIP64, so it counts as too large.
  package static func field32(_ value: Int) throws(ZipError) -> UInt32 {
    guard let field = UInt32(exactly: value), field != .max else { throw .tooLarge }
    return field
  }

  private struct EntryFields {
    let version: UInt16
    let flags: UInt16
    let method: UInt16
    let crc: UInt32
    let compressedSize: UInt32
    let size: UInt32
    let nameLength: UInt16
  }

  /// The fields local headers and central directory records share, in their common order.
  private func append(_ fields: EntryFields, to data: inout Data) {
    data.append16(fields.version)
    data.append16(fields.flags)
    data.append16(fields.method)
    data.append16(time)
    data.append16(date)
    data.append32(fields.crc)
    data.append32(fields.compressedSize)
    data.append32(fields.size)
    data.append16(fields.nameLength)
  }

  private func write(_ data: Data) throws(ZipError) {
    do {
      try handle.write(contentsOf: data)
    } catch {
      throw .cannotWrite(error.localizedDescription)
    }
  }

  private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
    let parts = Calendar(identifier: .gregorian).dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: date)
    let year = min(max((parts.year ?? 1980) - 1980, 0), 127)
    let time = (parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2
    let day = year << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1)
    return (UInt16(time), UInt16(day))
  }
}

extension Data {
  fileprivate mutating func append16(_ value: UInt16) {
    Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
  }

  fileprivate mutating func append32(_ value: UInt32) {
    Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
  }
}
