public struct ObserveDestinations: Sendable {
  private let monitor: any DestinationMonitor
  private let settings: any SettingsStore

  public init(monitor: any DestinationMonitor, settings: any SettingsStore) {
    self.monitor = monitor
    self.settings = settings
  }

  /// Re-emits the destination list each time a Kindle is plugged in or removed.
  public func callAsFunction() -> AsyncStream<[Destination]> {
    let volumes = monitor.volumes()
    let settings = settings
    return AsyncStream { continuation in
      let task = Task {
        for await current in volumes {
          let email = await settings.load().email?.kindleAddress
          continuation.yield(Self.destinations(email: email, volumes: current))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Plugged-in Kindles come first: a cable is faster and needs no internet.
  public static func destinations(email: KindleEmail?, volumes: [KindleVolume]) -> [Destination] {
    let usb = volumes.sorted { $0.name < $1.name }.map(Destination.usb)
    guard let email else { return usb }
    return usb + [.email(email)]
  }
}
