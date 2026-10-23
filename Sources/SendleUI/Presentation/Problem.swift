import Foundation
import SendleDomain

/// Settings' sections, in the order the front page lists them.
public enum SettingsSection: String, Hashable, Sendable, CaseIterable {
  case general
  case kindle
  case sender
  case usb

  package var title: String {
    switch self {
    case .general: "General"
    case .kindle: "Kindle"
    case .sender: "Sender"
    case .usb: "USB"
    }
  }
}

/// What one click can do about a problem.
public enum FixAction: Hashable, Sendable {
  case openPrivacySettings
  case openSettings(SettingsSection)
  case useDestination(DestinationKind)
  case eject(KindleVolume)
  case openURL(URL)
  case retry
}

public struct Fix: Hashable, Sendable {
  public let label: String
  public let action: FixAction

  public init(_ label: String, _ action: FixAction) {
    self.label = label
    self.action = action
  }
}

/// A failure as the user reads it: what happened, why, and the fix when there is one.
public struct Problem: Hashable, Sendable {
  public let title: String
  public let message: String?
  public let fix: Fix?

  public init(_ title: String, message: String? = nil, fix: Fix? = nil) {
    self.title = title
    self.message = message
    self.fix = fix
  }
}

extension MailProvider {
  package var displayName: String {
    switch self {
    case .gmail: "Gmail"
    case .iCloud: "iCloud Mail"
    case .fastmail: "Fastmail"
    case .custom: "The mail server"
    }
  }

  package var inlineName: String {
    self == .custom ? "the mail server" : displayName
  }
}
