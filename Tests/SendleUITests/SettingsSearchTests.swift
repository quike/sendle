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

  @Test func anEmptySearchFindsNothing() {
    #expect(SettingsSearch.results(for: "  ").isEmpty)
  }

  @Test func listsResultsInTheOrderOfTheSections() {
    #expect(
      SettingsSearch.results(for: "address").map(\.section) == [.kindle, .kindle, .sender])
  }

  @Test func everySettingNamesItsSection() {
    #expect(SettingsItem.appPassword.title == "App password")
    #expect(SettingsItem.showLogs.section == .general)
    #expect(SettingsItem.bokoLocation.section == .usb)
    #expect(SettingsSection.allCases.map(\.title) == ["General", "Kindle", "Sender", "USB"])
  }
}
