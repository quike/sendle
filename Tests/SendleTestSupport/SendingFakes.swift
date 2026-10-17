import Foundation
import SendleDomain
import os

public final class FakeEPUBPreparer: EPUBPreparer {
  private let prepared = OSAllocatedUnfairLock<[BookID]>(initialState: [])
  private let fixes: [EPUBFix]
  private let failure: SendFailure?

  public init(fixes: [EPUBFix] = [], failure: SendFailure? = nil) {
    self.fixes = fixes
    self.failure = failure
  }

  public var preparedIDs: [BookID] { prepared.withLock { $0 } }

  public func prepare(_ book: Book, in staging: URL) async throws(SendFailure) -> PreparedFile {
    prepared.withLock { $0.append(book.id) }
    if let failure { throw failure }
    return PreparedFile(
      url: staging.appending(path: "\(book.id.rawValue).epub"), format: .epub, fixes: fixes)
  }
}

public final class FakeFormatConverter: FormatConverter {
  private let isInstalled: OSAllocatedUnfairLock<Bool>
  private let converted = OSAllocatedUnfairLock<[PreparedFile]>(initialState: [])
  private let failure: SendFailure?

  public init(isAvailable: Bool = true, failure: SendFailure? = nil) {
    isInstalled = OSAllocatedUnfairLock(initialState: isAvailable)
    self.failure = failure
  }

  public var convertedFiles: [PreparedFile] { converted.withLock { $0 } }

  public var toolURL: URL? {
    isInstalled.withLock { $0 }
      ? URL(filePath: "/Applications/calibre.app/Contents/MacOS/ebook-convert") : nil
  }

  /// As if the user installed Calibre while Sendle runs.
  public func install() {
    isInstalled.withLock { $0 = true }
  }

  public func convert(
    _ file: PreparedFile,
    to format: FileFormat,
    in staging: URL
  ) async throws(SendFailure) -> PreparedFile {
    converted.withLock { $0.append(file) }
    if let failure { throw failure }
    return PreparedFile(
      url: staging.appending(path: "converted.\(format.fileExtension)"), format: format)
  }
}

public final class FakeDeliveryChannel: DeliveryChannel {
  public struct Delivery: Hashable, Sendable {
    public let file: PreparedFile
    public let name: String
  }

  public enum Behavior: Sendable {
    case succeed
    case fail(SendFailure)
    case hangUntilCancelled
    case hangThenFail(SendFailure)
  }

  private let script: OSAllocatedUnfairLock<[Behavior]>
  private let log = OSAllocatedUnfairLock<[Delivery]>(initialState: [])
  private let started = Signal()

  /// Each attempt consumes the next behavior; the last one repeats.
  public init(_ behaviors: Behavior...) {
    script = OSAllocatedUnfairLock(initialState: behaviors.isEmpty ? [.succeed] : behaviors)
  }

  public var deliveries: [Delivery] { log.withLock { $0 } }

  public func waitUntilDeliveryStarts() async {
    await started.wait()
  }

  public func deliver(
    _ file: PreparedFile,
    named baseName: String,
    progress: @Sendable (Double) async -> Void
  ) async throws(SendFailure) {
    log.withLock { $0.append(Delivery(file: file, name: baseName)) }
    await started.fire()
    switch nextBehavior() {
    case .succeed:
      await progress(0.5)
      await progress(1)
    case .fail(let failure):
      throw failure
    case .hangUntilCancelled:
      try? await Task.sleep(for: .seconds(3_600))
      throw .cancelled
    case .hangThenFail(let failure):
      try? await Task.sleep(for: .seconds(3_600))
      throw failure
    }
  }

  private func nextBehavior() -> Behavior {
    script.withLock { script in script.count > 1 ? script.removeFirst() : script[0] }
  }
}

public final class FakeDeliveryChannelFactory: DeliveryChannelFactory {
  public let deliveryChannel: FakeDeliveryChannel
  private let failure: SendFailure?
  private let requested = OSAllocatedUnfairLock<[Destination]>(initialState: [])

  public init(channel: FakeDeliveryChannel = FakeDeliveryChannel(), failure: SendFailure? = nil) {
    deliveryChannel = channel
    self.failure = failure
  }

  public var requestedDestinations: [Destination] { requested.withLock { $0 } }

  public func channel(for destination: Destination) async throws(SendFailure) -> any DeliveryChannel
  {
    requested.withLock { $0.append(destination) }
    if let failure { throw failure }
    return deliveryChannel
  }
}

public final class FakeStagingArea: StagingArea {
  public struct State: Sendable {
    public var made: [URL] = []
    public var removed: [URL] = []
    public var files: [URL: Data] = [:]
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let failure: SendFailure?

  public init(failure: SendFailure? = nil) {
    self.failure = failure
  }

  public var snapshot: State { state.withLock { $0 } }

  public func makeDirectory() throws(SendFailure) -> URL {
    if let failure { throw failure }
    return state.withLock { state in
      let url = URL(filePath: "/staging/\(state.made.count)", directoryHint: .isDirectory)
      state.made.append(url)
      return url
    }
  }

  public func writeFile(
    named name: String,
    contents: Data,
    in directory: URL
  ) throws(SendFailure) -> URL {
    let url = directory.appending(path: name)
    state.withLock { $0.files[url] = contents }
    return url
  }

  public func remove(_ directory: URL) {
    state.withLock { $0.removed.append(directory) }
  }
}
