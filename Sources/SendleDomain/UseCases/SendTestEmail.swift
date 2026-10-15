import Foundation

public struct SendTestEmail: Sendable {
  public static let documentName = "Sendle test"
  static let contents = Data("Sendle can reach your Kindle. You can delete this document.\n".utf8)

  private let settings: any SettingsStore
  private let channels: any DeliveryChannelFactory
  private let staging: any StagingArea

  public init(
    settings: any SettingsStore,
    channels: any DeliveryChannelFactory,
    staging: any StagingArea
  ) {
    self.settings = settings
    self.channels = channels
    self.staging = staging
  }

  /// Sends a one-line text document, which proves the login, the server and Amazon's
  /// approved-sender list in one go.
  public func callAsFunction() async throws(SendFailure) {
    guard let email = await settings.load().email else { throw .notConfigured }
    let directory = try staging.makeDirectory()
    defer { staging.remove(directory) }
    let url = try staging.writeFile(
      named: "\(Self.documentName).txt", contents: Self.contents, in: directory)
    let channel = try await channels.channel(for: .email(email.kindleAddress))
    try await channel.deliver(
      PreparedFile(url: url, format: .txt), named: Self.documentName, progress: { _ in })
  }
}
