import Foundation

public enum KindleAddressError: Error, Hashable, Sendable {
  case invalidAddress
  /// Addresses are kept with the email setup, which doesn't exist yet.
  case notConfigured
  /// The active address stays until another one is made active.
  case active
  case storage(StorageError)
}

/// The Kindle addresses saved in Settings, one of them active: sends by email go there.
public struct ManageKindleAddresses: Sendable {
  private let settings: any SettingsStore
  private let log: any ActivityLog

  public init(settings: any SettingsStore, log: any ActivityLog = NoActivityLog()) {
    self.settings = settings
    self.log = log
  }

  /// Saves the address, or finds it among the saved ones, and makes it the active one.
  public func add(_ text: String) async throws(KindleAddressError) -> [EmailSetupWarning] {
    let address = KindleEmail(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines))
    guard EmailAddress.isPlausible(address.rawValue) else { throw .invalidAddress }
    let before = try await makeActive(address)
    if let saved = before.savedSpelling(of: address) {
      log.info(.app, "\(saved.rawValue) is now the active Kindle address")
    } else {
      log.info(.app, "Saved \(address.rawValue) and made it the active Kindle address")
    }
    return address.isAmazonAddress ? [] : [.kindleAddressNotAmazon]
  }

  public func activate(_ address: KindleEmail) async throws(KindleAddressError) {
    let before = try await makeActive(address)
    let active = before.savedSpelling(of: address) ?? address
    log.info(.app, "\(active.rawValue) is now the active Kindle address")
  }

  public func remove(_ address: KindleEmail) async throws(KindleAddressError) {
    guard await settings.load().email?.kindleAddress.matches(address) != true else {
      throw .active
    }
    let before = try await change { settings in
      settings.kindleAddresses = settings.savedKindleAddresses.filter { !$0.matches(address) }
    }
    guard let removed = before.savedSpelling(of: address) else { return }
    log.info(.app, "Removed \(removed.rawValue) from the Kindle addresses")
  }

  /// Makes `address` active in its saved spelling, and returns the settings from before.
  private func makeActive(_ address: KindleEmail) async throws(KindleAddressError) -> AppSettings {
    try await change { settings in
      let saved = settings.saveKindleAddress(address)
      settings.email = settings.email?.with(kindleAddress: saved)
    }
  }

  /// Applies `update` while an email setup exists, and returns the settings from before it.
  private func change(
    _ update: @Sendable (inout AppSettings) -> Void
  ) async throws(KindleAddressError) -> AppSettings {
    guard await settings.load().email != nil else { throw .notConfigured }
    do throws(StorageError) {
      return try await settings.update(update)
    } catch {
      log.error(.app, "Couldn't save the Kindle addresses: \(error.detail)")
      throw .storage(error)
    }
  }
}
