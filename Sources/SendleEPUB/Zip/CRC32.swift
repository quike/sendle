import Foundation

/// The CRC-32 checksum ZIP uses (IEEE 802.3 polynomial, reflected).
package enum CRC32 {
  private static let table: [UInt32] = (0..<256).map { index in
    (0..<8).reduce(UInt32(index)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
  }

  package static func checksum(_ data: Data) -> UInt32 {
    let crc = data.withUnsafeBytes { bytes in
      bytes.reduce(UInt32.max) { crc, byte in
        table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
      }
    }
    return ~crc
  }
}
