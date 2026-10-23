import SendleDomain

package enum TitleCard {
  /// FNV-1a of the book ID, so a cover-less book keeps its colours: `hashValue` changes per launch.
  package static func paletteIndex(for id: BookID, count: Int) -> Int {
    var hash: UInt32 = 0x811c_9dc5
    for byte in id.rawValue.utf8 {
      hash = (hash ^ UInt32(byte)) &* 0x0100_0193
    }
    return Int(hash % UInt32(count))
  }
}
