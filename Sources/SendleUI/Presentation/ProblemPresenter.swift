import Foundation
import SendleDomain

/// The only place where domain errors become user-facing text (spec §4).
public enum ProblemPresenter {
  public static func problem(for error: LibraryError) -> Problem {
    switch error {
    case .accessDenied:
      Problem(
        "Sendle can't see your Books library",
        message: "macOS keeps the Books library private. Turn on Sendle under Full Disk Access; "
          + "Sendle only reads it.",
        fix: Fix("Open Privacy Settings", .openPrivacySettings))
    case .notFound:
      Problem(
        "Sendle can't find a Books library",
        message: "Open Books, add an EPUB or PDF, then try again.", fix: Fix("Retry", .retry))
    case .unsupportedSchema(let missing):
      Problem(
        "This version of Books isn't supported yet",
        message: "Its library has no \(missing.joined(separator: ", ")).")
    case .unreadable(let detail):
      Problem(
        "Sendle couldn't read your Books library", message: detail, fix: Fix("Retry", .retry))
    }
  }

  /// `kindleConnected` offers USB for books too large to email.
  public static func problem(for failure: SendFailure, kindleConnected: Bool = false) -> Problem {
    switch failure {
    case .authenticationFailed(let provider):
      Problem(
        "\(provider.displayName) didn't accept the password", message: passwordHint(provider),
        fix: Fix("Open Settings", .openSettings(.sender)))
    case .connectionFailed(let host):
      Problem(
        "Couldn't reach \(host)", message: "Check your internet connection, then try again.",
        fix: Fix("Retry", .retry))
    case .rejected(let detail):
      Problem("The mail server refused the message", message: detail)
    case .notConfigured:
      Problem("Set up your Kindle email first", fix: Fix("Open Settings", .openSettings(.kindle)))
    case .tooLarge(let bytes, let limit):
      Problem(
        tooLargeTitle(bytes: bytes, limit: limit),
        fix: kindleConnected ? Fix("Use USB", .useDestination(.usb)) : nil)
    case .protected:
      Problem("Protected by Apple (DRM), can't be sent")
    case .inCloudOnly:
      Problem("In iCloud only. Open it in Books to download.")
    case .missing:
      Problem("The file is no longer on this Mac")
    case .invalidBook(let detail):
      Problem("This EPUB is damaged and can't be prepared", message: detail)
    case .conversionUnavailable:
      Problem(
        "Your Kindle can't read EPUB over USB",
        message: "Sendle converts EPUBs with Calibre, which isn't installed.",
        fix: Fix("Send by email", .useDestination(.email)))
    case .conversionFailed(let output):
      Problem(
        "Calibre couldn't convert this book", message: output,
        fix: Fix("Send by email", .useDestination(.email)))
    case .deviceDisconnected:
      Problem("The Kindle was unplugged during the copy", fix: Fix("Retry", .retry))
    case .diskFull:
      Problem("Not enough space on the Kindle")
    case .localStorage(let detail):
      Problem("Couldn't write temporary files on this Mac", message: detail)
    case .cancelled:
      Problem("Cancelled")
    }
  }

  public static func settingsSetAside(_ file: URL) -> Problem {
    Problem(
      "Sendle couldn't read its settings",
      message: "They were moved to \(file.lastPathComponent) in Sendle's data folder. "
        + "Set up your Kindle email again.",
      fix: Fix("Open Settings", .openSettings(.kindle)))
  }

  private static func tooLargeTitle(bytes: Int64, limit: Int64) -> String {
    let size = Formatting.size(bytes)
    return limit == FormatPolicy.emailSizeLimit
      ? "\(size) is over Amazon's \(Formatting.size(limit)) email limit"
      : "\(size) is over your mail server's \(Formatting.size(limit)) limit"
  }

  private static func passwordHint(_ provider: MailProvider) -> String {
    switch provider {
    case .gmail: "Gmail needs an app password, which requires 2-Step Verification."
    case .iCloud: "iCloud Mail needs an app-specific password from account.apple.com."
    case .fastmail: "Fastmail needs an app password from its Privacy & Security settings."
    case .custom: "Check the sender address and app password in Settings."
    }
  }
}
