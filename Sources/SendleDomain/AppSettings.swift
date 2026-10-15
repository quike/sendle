public enum LibraryLayout: String, Sendable, Codable, CaseIterable {
  case grid
  case list
  case shelf
}

public struct AppSettings: Hashable, Sendable, Codable {
  public var email: EmailSettings?
  public var layout: LibraryLayout
  public var activeDestination: DestinationKind

  public static let defaults = AppSettings()

  public init(
    email: EmailSettings? = nil,
    layout: LibraryLayout = .grid,
    activeDestination: DestinationKind = .email
  ) {
    self.email = email
    self.layout = layout
    self.activeDestination = activeDestination
  }

  /// Files written by other versions still load: missing or unknown values fall back to defaults.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    email = try? container.decodeIfPresent(EmailSettings.self, forKey: .email)
    layout = (try? container.decodeIfPresent(LibraryLayout.self, forKey: .layout)) ?? .grid
    activeDestination =
      (try? container.decodeIfPresent(DestinationKind.self, forKey: .activeDestination)) ?? .email
  }
}
