import SendleUI
import Testing

struct SettingsSearchTests {
  @Test(
    arguments: [
      ("pass", [SettingsItem.appPassword]), ("debug", [.showLogs]), ("SMTP", [.mailServer]),
      ("gmail", [.mailProvider]), ("azw3", [.boko]), ("a–z", [.jumpBar]),
      ("amazon list", [.approvedSenders]), ("boko folder", [.bokoLocation]),
    ] as [(String, [SettingsItem])])
  func findsSettingsByNameAndByWhatTheyAreAbout(query: String, items: [SettingsItem]) {
    #expect(SettingsSearch.results(for: query) == items)
  }

  @Test func findsTheAZBarWithAHyphenOrNone() {
    #expect(SettingsSearch.results(for: "a-z") == [.jumpBar])
    #expect(SettingsSearch.results(for: "A-Z bar") == [.jumpBar])
    #expect(SettingsSearch.results(for: "az").first == .jumpBar)
  }

  @Test func findsTheFormatSettingByNameAndByTheFormatsItLabels() {
    #expect(SettingsSearch.results(for: "format") == [.showFormat])
    #expect(SettingsSearch.results(for: "epub").contains(.showFormat))
    #expect(SettingsItem.showFormat.title == "Show book format")
    #expect(SettingsItem.showFormat.section == .general)
  }

  @Test func searchFindsSortAuthorsBy() {
    #expect(SettingsSearch.results(for: "surname") == [.authorSort])
    #expect(SettingsSearch.results(for: "last name") == [.authorSort])
    #expect(SettingsSearch.results(for: "first name") == [.authorSort])
    #expect(SettingsSearch.results(for: "author") == [.authorSort])
    #expect(SettingsItem.authorSort.title == "Sort authors by")
    #expect(SettingsItem.authorSort.section == .general)
  }

  @Test func findsTheControlsStyleByNameAndByItsChoices() {
    #expect(SettingsSearch.results(for: "controls") == [.controls])
    #expect(SettingsSearch.results(for: "floating") == [.controls])
    #expect(SettingsSearch.results(for: "send bar") == [.controls])
    #expect(SettingsItem.controls.title == "Controls")
    #expect(SettingsItem.controls.section == .general)
  }

  @Test func anEmptySearchFindsNothing() {
    #expect(SettingsSearch.results(for: "  ").isEmpty)
  }

  @Test func listsResultsInTheOrderOfTheSections() {
    #expect(
      SettingsSearch.results(for: "address").map(\.section) == [.kindle, .kindle, .sender])
  }

  @Test func theProviderTilesStandForTheMailServerUnlessItIsOther() {
    #expect(SettingsItem.mailServer.onScreen(for: .gmail) == .mailProvider)
    #expect(SettingsItem.mailServer.onScreen(for: .custom) == .mailServer)
    #expect(SettingsItem.appPassword.onScreen(for: .gmail) == .appPassword)
  }

  @Test func everySettingNamesItsSection() {
    #expect(SettingsItem.appPassword.title == "App password")
    #expect(SettingsItem.showLogs.section == .general)
    #expect(SettingsItem.bokoLocation.section == .usb)
    #expect(
      SettingsSection.allCases.map(\.title)
        == ["General", "Kindle", "Sender", "USB", "Online lookup"])
  }

  @Test func searchFindsOnlineLookup() {
    for word in [
      "lookup", "online", "internet", "Open Library", "Google", "Apple", "ISBN", "metadata",
      "details",
    ] {
      #expect(SettingsSearch.results(for: word).contains(.lookupSources), "\(word)")
    }
    #expect(SettingsItem.lookupSources.title == "Online lookup sources")
    #expect(SettingsItem.lookupSources.section == .lookup)
  }

  @Test func searchFindsTheGoogleBooksKey() {
    #expect(SettingsSearch.results(for: "api key") == [.googleBooksKey])
    #expect(SettingsSearch.results(for: "google").contains(.googleBooksKey))
    #expect(SettingsItem.googleBooksKey.title == "Google Books API key")
    #expect(SettingsItem.googleBooksKey.section == .lookup)
  }
}
