import Foundation
import Observation
import SendleDomain

/// The settings sheet: Kindle, sender, USB and general (spec §3.5).
@Observable @MainActor
public final class SettingsViewModel {
  package var section = SettingsSection.kindle
  package let form: EmailForm
  package private(set) var launchAtLogin = LoginItemStatus.disabled
  package private(set) var launchAtLoginError: String?
  /// boko, when it is installed.
  package private(set) var boko: URL?

  private let settings: any SettingsStore
  private let loginItem: any LoginItem
  private let converter: any FormatConverter

  public init(
    configure: ConfigureEmail,
    sendTest: SendTestEmail,
    settings: any SettingsStore,
    loginItem: any LoginItem,
    converter: any FormatConverter
  ) {
    form = EmailForm(configure: configure, sendTest: sendTest)
    self.settings = settings
    self.loginItem = loginItem
    self.converter = converter
  }

  /// Starts from what is saved, so edits that were never saved are gone.
  package func open(at section: SettingsSection) async {
    self.section = section
    form.fill(from: await settings.load().email)
    launchAtLogin = loginItem.status
    launchAtLoginError = nil
    boko = converter.toolURL
  }

  /// The setup is checked as a whole; when the fields to fix are in the other section, go there.
  package func save() async -> Bool {
    guard await form.save() else {
      let sections = Set(
        form.issues.map { $0 == .invalidKindleAddress ? SettingsSection.kindle : .sender })
      if !sections.isEmpty, !sections.contains(section) {
        section = sections.contains(.kindle) ? .kindle : .sender
      }
      return false
    }
    return true
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

  package var bokoTitle: String {
    boko == nil ? "boko not found" : "boko found"
  }

  package var bokoNote: String {
    boko == nil
      ? "Your Kindle can't read EPUB, so Sendle converts EPUBs with boko before copying them. "
        + "Until it's installed, PDFs go over USB and EPUBs go by email."
      : "EPUBs are converted to AZW3 before they're copied to your Kindle."
  }
}
