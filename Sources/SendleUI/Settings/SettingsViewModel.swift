import Foundation
import Observation
import SendleDomain

/// The settings sheet: Kindle, sender and general (spec §3.5).
@Observable @MainActor
public final class SettingsViewModel {
  package var section = SettingsSection.kindle
  package let form: EmailForm
  package private(set) var launchAtLogin = LoginItemStatus.disabled
  package private(set) var launchAtLoginError: String?
  package let sendTestHint = "Test emails arrive with email support."

  private let settings: any SettingsStore
  private let loginItem: any LoginItem

  public init(configure: ConfigureEmail, settings: any SettingsStore, loginItem: any LoginItem) {
    form = EmailForm(configure: configure)
    self.settings = settings
    self.loginItem = loginItem
  }

  /// Starts from what is saved, so edits that were never saved are gone.
  package func open(at section: SettingsSection) async {
    self.section = section
    form.fill(from: await settings.load().email)
    launchAtLogin = loginItem.status
    launchAtLoginError = nil
  }

  package func save() async -> Bool {
    await form.save()
  }

  package func setLaunchAtLogin(_ enabled: Bool) {
    do {
      try loginItem.setEnabled(enabled)
      launchAtLoginError = nil
    } catch {
      launchAtLoginError = "Couldn't change this: \(error.localizedDescription)"
    }
    launchAtLogin = loginItem.status
  }

  package var launchAtLoginNote: String? {
    switch launchAtLogin {
    case .requiresApproval: "Approve Sendle in System Settings › General › Login Items."
    case .unavailable: "Launch at login works once Sendle runs as an app."
    case .enabled, .disabled: nil
    }
  }
}
