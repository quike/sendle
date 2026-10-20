public enum LibraryLayout: String, Sendable, Codable, CaseIterable {
  case grid
  case list
  case shelf
}

public enum LibrarySort: String, Sendable, Codable, CaseIterable {
  /// Newest first, as Books adds them.
  case recent
  case title
  case author
}

/// How the A–Z bar shows while the library is sorted by title or author.
public enum JumpBarStyle: String, Sendable, Codable, CaseIterable {
  /// Every letter, always there.
  case full
  /// Only the letters with books, shown on hover.
  case compact
}

/// Where the send bar and the A–Z bar sit.
public enum ControlsStyle: String, Sendable, Codable, CaseIterable {
  /// Inside the panel's card.
  case attached
  /// On cards of their own, below and beside the panel's card.
  case floating
}

/// How authors are filed: "Sáenz, Eva García" under surname, "Eva García Sáenz" under first name.
public enum AuthorSort: String, Sendable, Codable, CaseIterable {
  case surname
  case firstName
}

public struct AppSettings: Hashable, Sendable, Codable {
  public var email: EmailSettings?
  public var layout: LibraryLayout
  public var activeDestination: DestinationKind
  public var sort: LibrarySort
  public var jumpBar: JumpBarStyle
  public var controls: ControlsStyle
  public var showsFormat: Bool
  public var showsLogs: Bool
  public var authorSort: AuthorSort
  /// Kindle addresses kept for later; `email.kindleAddress` is the active one.
  public var kindleAddresses: [KindleEmail]
  /// The boko the user chose; nil looks in the usual folders.
  public var bokoPath: String?

  public static let defaults = AppSettings()

  public init(
    email: EmailSettings? = nil,
    layout: LibraryLayout = .grid,
    activeDestination: DestinationKind = .email,
    sort: LibrarySort = .recent,
    jumpBar: JumpBarStyle = .full,
    controls: ControlsStyle = .floating,
    showsFormat: Bool = true,
    showsLogs: Bool = false,
    authorSort: AuthorSort = .surname,
    kindleAddresses: [KindleEmail] = [],
    bokoPath: String? = nil
  ) {
    self.email = email
    self.layout = layout
    self.activeDestination = activeDestination
    self.sort = sort
    self.jumpBar = jumpBar
    self.controls = controls
    self.showsFormat = showsFormat
    self.showsLogs = showsLogs
    self.authorSort = authorSort
    self.kindleAddresses = kindleAddresses
    self.bokoPath = bokoPath
  }

  /// A missing or unknown value falls back to its default. An unreadable email block throws
  /// instead, so the store keeps the file aside rather than losing the setup.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    email = try container.decodeIfPresent(EmailSettings.self, forKey: .email)
    layout = (try? container.decodeIfPresent(LibraryLayout.self, forKey: .layout)) ?? .grid
    activeDestination =
      (try? container.decodeIfPresent(DestinationKind.self, forKey: .activeDestination)) ?? .email
    sort = (try? container.decodeIfPresent(LibrarySort.self, forKey: .sort)) ?? .recent
    jumpBar = (try? container.decodeIfPresent(JumpBarStyle.self, forKey: .jumpBar)) ?? .full
    controls =
      (try? container.decodeIfPresent(ControlsStyle.self, forKey: .controls)) ?? .floating
    showsFormat = (try? container.decodeIfPresent(Bool.self, forKey: .showsFormat)) ?? true
    showsLogs = (try? container.decodeIfPresent(Bool.self, forKey: .showsLogs)) ?? false
    authorSort =
      (try? container.decodeIfPresent(AuthorSort.self, forKey: .authorSort)) ?? .surname
    kindleAddresses =
      (try? container.decodeIfPresent([KindleEmail].self, forKey: .kindleAddresses)) ?? []
    bokoPath = (try? container.decodeIfPresent(String.self, forKey: .bokoPath)) ?? nil
  }

  /// The saved Kindle addresses with the active one among them, as a file from before the list
  /// existed holds only the active one.
  public var savedKindleAddresses: [KindleEmail] {
    guard let active = email?.kindleAddress, !kindleAddresses.contains(where: active.matches)
    else { return kindleAddresses }
    return [active] + kindleAddresses
  }

  /// How `address` is spelled among the saved Kindle addresses, whatever case it was typed in.
  public func savedSpelling(of address: KindleEmail) -> KindleEmail? {
    savedKindleAddresses.first(where: address.matches)
  }

  /// Saves `address` unless it is saved already, and returns its saved spelling.
  public mutating func saveKindleAddress(_ address: KindleEmail) -> KindleEmail {
    kindleAddresses = savedKindleAddresses
    if let saved = savedSpelling(of: address) { return saved }
    kindleAddresses.append(address)
    return address
  }
}
