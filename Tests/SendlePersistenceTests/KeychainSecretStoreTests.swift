import Foundation
import SendleDomain
import SendlePersistence
import Testing

/// Uses the real login keychain under a throwaway service name, removed after each test.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SENDLE_SKIP_KEYCHAIN_TESTS"] == nil))
struct KeychainSecretStoreTests {
  let store = KeychainSecretStore(service: "io.github.quike.Sendle.tests.\(UUID().uuidString)")
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

  @Test func removingAMissingPasswordIsNotAnError() {
    #expect(throws: Never.self) { try store.removePassword(for: "nobody@example.com") }
  }
}
