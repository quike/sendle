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

public struct AppSettings: Hashable, Sendable, Codable {
  public var email: EmailSettings?
  public var layout: LibraryLayout
  public var activeDestination: DestinationKind
  public var sort: LibrarySort
  public var jumpBar: JumpBarStyle
  public var showsLogs: Bool
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
    showsLogs: Bool = false,
    kindleAddresses: [KindleEmail] = [],
    bokoPath: String? = nil
  ) {
    self.email = email
    self.layout = layout
    self.activeDestination = activeDestination
    self.sort = sort
    self.jumpBar = jumpBar
    self.showsLogs = showsLogs
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
    showsLogs = (try? container.decodeIfPresent(Bool.self, forKey: .showsLogs)) ?? false
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
}
