import SendleDomain
import SendleTestSupport
import Testing

struct ManageKindleAddressesTests {
  let paperwhite = KindleEmail(rawValue: "pw5@kindle.com")
  let settings = InMemorySettingsStore(AppSettings(email: .fixture))
  let log = FakeActivityLog()
  var addresses: ManageKindleAddresses { ManageKindleAddresses(settings: settings, log: log) }

  @Test func aNewAddressIsSavedAndBecomesTheActiveOne() async throws {
    let warnings = try await addresses.add(" pw5@kindle.com\n")

    #expect(warnings.isEmpty)
    #expect(await settings.settings.email?.kindleAddress == paperwhite)
    #expect(await settings.settings.savedKindleAddresses == [.fixture, paperwhite])
    #expect(log.summary == ["info APP Saved pw5@kindle.com and made it the active Kindle address"])
  }

  @Test func addingAnAddressAgainMakesTheSavedOneActive() async throws {
    _ = try await addresses.add("pw5@kindle.com")

    _ = try await addresses.add("Reader@Kindle.com")

    #expect(await settings.settings.email?.kindleAddress == .fixture)
    #expect(await settings.settings.savedKindleAddresses == [.fixture, paperwhite])
    #expect(log.summary.last == "info APP reader@kindle.com is now the active Kindle address")
  }

  @Test func activatingAnAddressInAnotherCaseKeepsTheSavedSpelling() async throws {
    _ = try await addresses.add("pw5@kindle.com")

    try await addresses.activate(KindleEmail(rawValue: "PW5@Kindle.com"))

    #expect(await settings.settings.email?.kindleAddress == paperwhite)
    #expect(await settings.settings.savedKindleAddresses == [.fixture, paperwhite])
    #expect(log.summary.last == "info APP pw5@kindle.com is now the active Kindle address")
  }

  @Test func warnsAboutAnAddressAmazonWontDeliverTo() async throws {
    #expect(try await addresses.add("reader@gmail.com") == [.kindleAddressNotAmazon])
  }

  @Test func refusesSomethingThatIsNotAnAddress() async {
    await #expect(throws: KindleAddressError.invalidAddress) {
      try await addresses.add("reader")
    }
    #expect(await settings.settings.savedKindleAddresses == [.fixture])
  }

  @Test func needsAnEmailSetupFirstAndLeavesTheFileAlone() async {
    let empty = ManageKindleAddresses(
      settings: InMemorySettingsStore(failure: .writeFailed("read-only")), log: log)

    await #expect(throws: KindleAddressError.notConfigured) {
      try await empty.add("pw5@kindle.com")
    }
    await #expect(throws: KindleAddressError.notConfigured) {
      try await empty.activate(paperwhite)
    }
    await #expect(throws: KindleAddressError.notConfigured) {
      try await empty.remove(paperwhite)
    }
    #expect(log.summary.isEmpty)
  }

  @Test func activatesASavedAddress() async throws {
    _ = try await addresses.add("pw5@kindle.com")

    try await addresses.activate(.fixture)

    #expect(await settings.settings.email?.kindleAddress == .fixture)
    #expect(await settings.settings.email?.senderAddress == "me@gmail.com")
    #expect(log.summary.last == "info APP reader@kindle.com is now the active Kindle address")
  }

  @Test func removesAnAddressButNeverTheActiveOne() async throws {
    _ = try await addresses.add("pw5@kindle.com")
    await #expect(throws: KindleAddressError.active) {
      try await addresses.remove(paperwhite)
    }

    try await addresses.remove(.fixture)

    #expect(await settings.settings.savedKindleAddresses == [paperwhite])
    #expect(log.summary.last == "info APP Removed reader@kindle.com from the Kindle addresses")
  }

  @Test func theActiveAddressStaysWhateverItsCase() async throws {
    await #expect(throws: KindleAddressError.active) {
      try await addresses.remove(KindleEmail(rawValue: "READER@kindle.com"))
    }
    #expect(await settings.settings.savedKindleAddresses == [.fixture])
  }

  @Test func removingAnAddressThatIsNotSavedLogsNothing() async throws {
    try await addresses.remove(paperwhite)

    #expect(await settings.settings.savedKindleAddresses == [.fixture])
    #expect(log.summary.isEmpty)
  }

  @Test func saysWhenTheAddressesCouldNotBeSaved() async {
    let failing = ManageKindleAddresses(
      settings: InMemorySettingsStore(
        AppSettings(email: .fixture), failure: .writeFailed("disk full")),
      log: log)

    await #expect(throws: KindleAddressError.storage(.writeFailed("disk full"))) {
      try await failing.activate(paperwhite)
    }
    #expect(log.summary == ["error APP Couldn't save the Kindle addresses: disk full"])
  }
}
