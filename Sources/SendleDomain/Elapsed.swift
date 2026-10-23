import Foundation

/// How long something took, as the logs write it: English, the same on every Mac.
public enum Elapsed {
  /// Seconds with one decimal: "0.4 s", "12.3 s".
  public static func text(_ duration: Duration) -> String {
    let parts = duration.components
    return String(format: "%.1f s", Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
  }
}
