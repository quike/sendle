import CoreGraphics

/// Where each letter of the A–Z bar sits: evenly spaced down its height.
package enum RailLayout {
  /// The letter under `y`; a drag past either end keeps the end letter.
  package static func letter(at y: CGFloat, height: CGFloat, letters: [String]) -> String? {
    guard !letters.isEmpty, height > 0 else { return nil }
    let index = Int(y / (height / CGFloat(letters.count)))
    return letters[min(max(index, 0), letters.count - 1)]
  }
}
