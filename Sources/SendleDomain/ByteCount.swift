import Foundation

/// Sizes as Sendle writes them: English, and the same on every Mac whatever its locale.
public enum ByteCount {
  /// Decimal units, as Finder and Amazon count them: "612 KB", "1.4 MB", "62 MB".
  /// `precise` keeps one decimal at every size: "21.2 MB".
  public static func text(_ bytes: Int64, precise: Bool = false) -> String {
    guard bytes >= 1_000 else { return bytes == 1 ? "1 byte" : "\(bytes) bytes" }
    var value = Double(bytes) / 1_000
    for unit in ["KB", "MB", "GB"] {
      let decimal = precise || (unit != "KB" && value < 10)
      let rounded = decimal ? (value * 10).rounded() / 10 : value.rounded()
      if rounded < 1_000 || unit == "GB" {
        return rounded == rounded.rounded() && !precise
          ? "\(Int(rounded)) \(unit)" : String(format: "%.1f %@", rounded, unit)
      }
      value /= 1_000
    }
    return "\(bytes) bytes"
  }
}
