public protocol DestinationMonitor: Sendable {
  /// An independent stream per call: it starts with the mounted Kindles and emits the full list
  /// whenever it changes.
  func volumes() -> AsyncStream<[KindleVolume]>
}
