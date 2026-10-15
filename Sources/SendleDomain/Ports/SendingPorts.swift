import Foundation

public protocol EPUBPreparer: Sendable {
  /// Packages the book's EPUB into `staging` and applies the Kindle fixes.
  func prepare(_ book: Book, in staging: URL) async throws(SendFailure) -> PreparedFile
}

public protocol FormatConverter: Sendable {
  var isAvailable: Bool { get }
  func convert(
    _ file: PreparedFile,
    to format: FileFormat,
    in staging: URL
  ) async throws(SendFailure) -> PreparedFile
}

public protocol StagingArea: Sendable {
  func makeDirectory() throws(SendFailure) -> URL
  func writeFile(named name: String, contents: Data, in directory: URL) throws(SendFailure) -> URL
  func remove(_ directory: URL)
}

public protocol DeliveryChannel: Sendable {
  /// Delivers `file` under the name `baseName` plus the file's extension.
  func deliver(
    _ file: PreparedFile,
    named baseName: String,
    progress: @Sendable (Double) async -> Void
  ) async throws(SendFailure)
}

public protocol DeliveryChannelFactory: Sendable {
  func channel(for destination: Destination) async throws(SendFailure) -> any DeliveryChannel
}
