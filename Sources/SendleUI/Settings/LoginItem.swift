public enum LoginItemStatus: Sendable {
  case enabled
  case disabled
  /// macOS registered it but waits for the user in System Settings › Login Items.
  case requiresApproval
  /// Not running from an app bundle, so there's nothing to register.
  case unavailable
}

/// Launch at login. The app implements it with `SMAppService.mainApp`.
@MainActor
public protocol LoginItem: AnyObject {
  var status: LoginItemStatus { get }
  func setEnabled(_ enabled: Bool) throws
}
