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
    let updated = try await change { settings in
      var saved = settings.savedKindleAddresses
      let active = saved.first(where: address.matches) ?? address
      if !saved.contains(where: address.matches) { saved.append(address) }
      settings.kindleAddresses = saved
      settings.email = settings.email?.with(kindleAddress: active)
    }
    log.info(.app, "Saved \(updated.rawValue) and made it the active Kindle address")
    return updated.isAmazonAddress ? [] : [.kindleAddressNotAmazon]
  }

  public func activate(_ address: KindleEmail) async throws(KindleAddressError) {
    try await change { settings in
      settings.kindleAddresses = settings.savedKindleAddresses
      if !settings.kindleAddresses.contains(where: address.matches) {
        settings.kindleAddresses.append(address)
      }
      settings.email = settings.email?.with(kindleAddress: address)
    }
    log.info(.app, "\(address.rawValue) is now the active Kindle address")
  }

  public func remove(_ address: KindleEmail) async throws(KindleAddressError) {
    let current = await settings.load()
    guard current.email.map({ !$0.kindleAddress.matches(address) }) ?? true else {
      throw .active
    }
    try await change { settings in
      guard settings.email.map({ !$0.kindleAddress.matches(address) }) ?? true else { return }
      settings.kindleAddresses = settings.savedKindleAddresses.filter { !$0.matches(address) }
    }
    log.info(.app, "Removed \(address.rawValue) from the Kindle addresses")
  }

  /// Applies `change` while an email setup exists, and returns the active address after it.
  @discardableResult
  private func change(
    _ change: @escaping @Sendable (inout AppSettings) -> Void
  ) async throws(KindleAddressError) -> KindleEmail {
    let previous: AppSettings
    do throws(StorageError) {
      previous = try await settings.update { settings in
        guard settings.email != nil else { return }
        change(&settings)
      }
    } catch {
      log.error(.app, "Couldn't save the Kindle addresses: \(error.detail)")
      throw .storage(error)
    }
    guard previous.email != nil, let active = await settings.load().email?.kindleAddress else {
      throw .notConfigured
    }
    return active
  }
}

extension EmailSettings {
  public func with(kindleAddress: KindleEmail) -> EmailSettings {
    EmailSettings(
      kindleAddress: kindleAddress, senderAddress: senderAddress, provider: provider,
      server: server)
  }
}

extension StorageError {
  /// What went wrong, in a few words for the logs.
  public var detail: String {
    switch self {
    case .writeFailed(let detail): detail
    case .keychain(let status): "the Keychain refused it (\(status))"
    }
  }
}
