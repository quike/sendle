import Foundation
import SendleDomain

/// Sizes and ages as the panel shows them: English, and the same on every Mac whatever its locale.
package enum Formatting {
  package static func size(_ bytes: Int64, precise: Bool = false) -> String {
    ByteCount.text(bytes, precise: precise)
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

  /// "12 Oct 2025", in English whatever the Mac's locale.
  package static func day(_ date: Date, in zone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.dateFormat = "d MMM yyyy"
    return formatter.string(from: date)
  }
}
