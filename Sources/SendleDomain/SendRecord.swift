import Foundation

public enum SendOutcome: String, Sendable, Codable, CaseIterable {
  case sent
  case failed
}

public struct SendRecord: Hashable, Sendable, Codable {
  public let bookID: BookID
  public let destination: DestinationKind
  public let date: Date
  public let outcome: SendOutcome

  public init(bookID: BookID, destination: DestinationKind, date: Date, outcome: SendOutcome) {
    self.bookID = bookID
    self.destination = destination
    self.date = date
    self.outcome = outcome
  }
}
