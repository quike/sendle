import Foundation
import SendleDomain

/// Every setting the search can find, in the order the sections list them.
package enum SettingsItem: CaseIterable, Sendable {
  case launchAtLogin
  case controls
  case jumpBar
  case authorSort
  case showFormat
  case showLogs
  case kindleAddresses
  case addAddress
  case approvedSenders
  case mailProvider
  case senderAddress
  case appPassword
  case mailServer
  case sendTest
  case boko
  case bokoLocation

  package var title: String {
    switch self {
    case .launchAtLogin: "Launch at login"
    case .controls: "Controls"
    case .jumpBar: "A–Z bar"
    case .authorSort: "Sort authors by"
    case .showFormat: "Show book format"
    case .showLogs: "Show logs"
    case .kindleAddresses: "Kindle addresses"
    case .addAddress: "Add address"
    case .approvedSenders: "Approved senders"
    case .mailProvider: "Mail provider"
    case .senderAddress: "Sender address"
    case .appPassword: "App password"
    case .mailServer: "Mail server"
    case .sendTest: "Send test"
    case .boko: "boko"
    case .bokoLocation: "boko location"
    }
  }

  package var section: SettingsSection {
    switch self {
    case .launchAtLogin, .controls, .jumpBar, .authorSort, .showFormat, .showLogs: .general
    case .kindleAddresses, .addAddress, .approvedSenders: .kindle
    case .mailProvider, .senderAddress, .appPassword, .mailServer, .sendTest: .sender
    case .boko, .bokoLocation: .usb
    }
  }

  /// What the page marks for this setting: the mail server fields show only for Other, so for
  /// the other providers the tiles stand in for them.
  package func onScreen(for provider: MailProvider) -> SettingsItem {
    self == .mailServer && provider != .custom ? .mailProvider : self
  }

  /// Other words people may look for it by.
  var keywords: [String] {
    switch self {
    case .launchAtLogin: ["startup", "start", "open"]
    case .controls: ["attached", "floating", "send bar", "cards", "detached"]
    case .jumpBar: ["a-z", "az", "alphabet", "letters", "index", "sort", "rail", "jump"]
    case .authorSort: ["author", "sort", "surname", "first name", "last name"]
    case .showFormat: ["epub", "pdf", "badge", "label", "cover", "type"]
    case .showLogs: ["debug", "troubleshooting", "diagnostics"]
    case .kindleAddresses: ["send to kindle", "active", "email address"]
    case .addAddress: ["new", "kindle", "email address"]
    case .approvedSenders: ["amazon", "approved", "list", "personal document"]
    case .mailProvider: ["gmail", "icloud", "fastmail", "other", "account"]
    case .senderAddress: ["from", "email address", "account"]
    case .appPassword: ["keychain", "app-specific", "sign in"]
    case .mailServer: ["smtp", "host", "port", "tls", "starttls"]
    case .sendTest: ["check", "try"]
    case .boko: ["converter", "convert", "azw3", "epub"]
    case .bokoLocation: ["choose", "path", "folder", "where"]
    }
  }
}

package enum SettingsSearch {
  /// The settings whose name or keywords hold every word of `query`, ignoring case and accents.
  package static func results(for query: String) -> [SettingsItem] {
    let words = query.split(whereSeparator: \.isWhitespace)
    guard !words.isEmpty else { return [] }
    return SettingsItem.allCases.filter { item in
      let text = ([item.title] + item.keywords).joined(separator: " ")
      return words.allSatisfy {
        text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
    }
  }
}
