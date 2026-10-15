import Foundation
import Security
import SendleDomain

/// Generic passwords in the login keychain, one item per sender address.
public struct KeychainSecretStore: SecretStore {
  public static let defaultService = "io.github.quike.Sendle.smtp"

  private let service: String

  public init(service: String = defaultService) {
    self.service = service
  }

  public func password(for account: String) throws(StorageError) -> String? {
    var query = baseQuery(for: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data else { return nil }
      return String(decoding: data, as: UTF8.self)
    case errSecItemNotFound:
      return nil
    default:
      throw .keychain(status: status)
    }
  }

  public func setPassword(_ password: String, for account: String) throws(StorageError) {
    let data = Data(password.utf8)
    var status = SecItemUpdate(
      baseQuery(for: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = baseQuery(for: account)
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      status = SecItemAdd(item as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw .keychain(status: status) }
  }

  public func removePassword(for account: String) throws(StorageError) {
    let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw .keychain(status: status)
    }
  }

  private func baseQuery(for account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
