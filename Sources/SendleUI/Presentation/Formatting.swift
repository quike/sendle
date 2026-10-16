import Foundation

/// Sizes and ages as the panel shows them: English, and the same on every Mac whatever its locale.
package enum Formatting {
  /// Decimal units, as Finder and Amazon count them: "612 KB", "1.4 MB", "62 MB".
  package static func size(_ bytes: Int64) -> String {
    guard bytes >= 1_000 else { return bytes == 1 ? "1 byte" : "\(bytes) bytes" }
    var value = Double(bytes) / 1_000
    for unit in ["KB", "MB", "GB"] {
      let rounded = unit != "KB" && value < 10 ? (value * 10).rounded() / 10 : value.rounded()
      if rounded < 1_000 || unit == "GB" {
        return rounded == rounded.rounded()
          ? "\(Int(rounded)) \(unit)" : String(format: "%.1f %@", rounded, unit)
      }
      value /= 1_000
    }
    return "\(bytes) bytes"
  }

  /// "just now", "5m ago", "3h ago", "2d ago", "4mo ago", "1y ago".
  package static func age(of date: Date, now: Date) -> String {
    let seconds = Int(now.timeIntervalSince(date))
    let day = 86_400
    switch seconds {
    case ..<60: return "just now"
    case ..<3_600: return "\(seconds / 60)m ago"
    case ..<day: return "\(seconds / 3_600)h ago"
    case ..<(30 * day): return "\(seconds / day)d ago"
    case ..<(365 * day): return "\(seconds / (30 * day))mo ago"
    default: return "\(seconds / (365 * day))y ago"
    }
  }
}
