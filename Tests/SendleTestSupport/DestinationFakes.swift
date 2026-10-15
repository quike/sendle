import SendleDomain

public final class FakeDestinationMonitor: DestinationMonitor {
  private let stream: AsyncStream<[KindleVolume]>
  public let continuation: AsyncStream<[KindleVolume]>.Continuation

  public init() {
    (stream, continuation) = AsyncStream.makeStream()
  }

  public func volumes() -> AsyncStream<[KindleVolume]> {
    stream
  }
}
