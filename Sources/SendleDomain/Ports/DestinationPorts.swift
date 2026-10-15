public protocol DestinationMonitor: Sendable {
  /// Emits the full list of mounted Kindles whenever it changes, starting with the current list.
  func volumes() -> AsyncStream<[KindleVolume]>
}
