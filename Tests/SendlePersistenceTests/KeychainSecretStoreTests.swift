import Foundation
import Security
import SendleDomain
import SendlePersistence
import Testing

/// Uses the real login keychain under a throwaway service name, removed after each test.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SENDLE_SKIP_KEYCHAIN_TESTS"] == nil))
struct KeychainSecretStoreTests {
  let service = "io.github.quike.Sendle.tests.\(UUID().uuidString)"
  var store: KeychainSecretStore { KeychainSecretStore(service: service) }
  let account = "me@gmail.com"

  @Test func returnsNilForAnUnknownAccount() throws {
    #expect(try store.password(for: account) == nil)
  }

  @Test func savesUpdatesAndRemovesAPassword() throws {
    defer { try? store.removePassword(for: account) }

    try store.setPassword("first", for: account)
    #expect(try store.password(for: account) == "first")

    try store.setPassword("second", for: account)
    #expect(try store.password(for: account) == "second")

    try store.removePassword(for: account)
    #expect(try store.password(for: account) == nil)
  }

  @Test func refusesAPasswordThatIsNotUTF8() throws {
    defer { try? store.removePassword(for: account) }
    let item: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account, kSecValueData as String: Data([0xFF, 0xFE, 0x00]),
    ]
    #expect(SecItemAdd(item as CFDictionary, nil) == errSecSuccess)

    #expect(throws: StorageError.keychain(status: errSecDecode)) {
      try store.password(for: account)
    }
  }

  @Test func removingAMissingPasswordIsNotAnError() {
    #expect(throws: Never.self) { try store.removePassword(for: "nobody@example.com") }
  }
}
