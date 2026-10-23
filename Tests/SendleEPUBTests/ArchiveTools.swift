import Foundation
import SendleEPUB

/// A local file header, read straight from an archive's bytes.
struct LocalHeader: Equatable {
  let name: String
  let flags: UInt16
  let method: UInt16
  let crc: UInt32
  let compressedSize: Int
  let size: Int
  let extraLength: Int
}

/// The local headers from the start of `archive`, in order, the way a reader that sniffs the
/// first entry sees them.
func localHeaders(in archive: Data) -> [LocalHeader] {
  var headers: [LocalHeader] = []
  var offset = 0
  while offset + 30 <= archive.count, archive.uint32(at: offset) == 0x0403_4B50 {
    let nameLength = Int(archive.uint16(at: offset + 26))
    let extraLength = Int(archive.uint16(at: offset + 28))
    let compressedSize = Int(archive.uint32(at: offset + 18))
    let nameStart = offset + 30
    headers.append(
      LocalHeader(
        name: String(decoding: archive[nameStart..<nameStart + nameLength], as: UTF8.self),
        flags: archive.uint16(at: offset + 6),
        method: archive.uint16(at: offset + 8),
        crc: archive.uint32(at: offset + 14),
        compressedSize: compressedSize,
        size: Int(archive.uint32(at: offset + 22)),
        extraLength: extraLength))
    offset = nameStart + nameLength + extraLength + compressedSize
  }
  return headers
}

/// Writes `entries` in order with `ZipWriter`, the first one stored.
func writeArchive(_ entries: [(String, Data)], to url: URL) throws {
  let writer = try ZipWriter(creatingFileAt: url)
  for (index, (name, data)) in entries.enumerated() {
    try writer.add(name, data: data, method: index == 0 ? .stored : .deflated)
  }
  try writer.finish()
}

/// Runs a command-line tool and returns its exit status and combined output.
func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
  let process = Process()
  process.executableURL = URL(filePath: tool)
  process.arguments = arguments
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe
  try process.run()
  let output = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return (process.terminationStatus, String(decoding: output, as: UTF8.self))
}

extension Data {
  func uint16(at offset: Int) -> UInt16 {
    withUnsafeBytes {
      UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
    }
  }

  func uint32(at offset: Int) -> UInt32 {
    withUnsafeBytes {
      UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
  }
}
