public enum EjectError: Error, Hashable, Sendable {
  /// Something still has a file open on the Kindle.
  case inUse
  case failed(String)
}

public protocol KindleEjector: Sendable {
  func eject(_ volume: KindleVolume) async throws(EjectError)
}

public protocol DestinationMonitor: Sendable {
  /// An independent stream per call: it starts with the mounted Kindles and emits the full list
  /// whenever it changes.
  func volumes() -> AsyncStream<[KindleVolume]>
}
