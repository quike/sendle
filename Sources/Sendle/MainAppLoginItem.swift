import Foundation
import SendleUI
import ServiceManagement

/// Launch at login through `SMAppService.mainApp`, which needs Sendle to run as an app bundle.
@MainActor
final class MainAppLoginItem: LoginItem {
  var status: LoginItemStatus {
    guard Bundle.main.bundleURL.pathExtension == "app" else { return .unavailable }
    switch SMAppService.mainApp.status {
    case .enabled: return .enabled
    case .requiresApproval: return .requiresApproval
    // An app that never registered can read as not found; registering still works.
    case .notRegistered, .notFound: return .disabled
    @unknown default: return .disabled
    }
  }

  func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}
