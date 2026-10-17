import Foundation
import SendleAppleBooks
import SendleCovers
import SendleDomain
import SendleEPUB
import SendleKindleUSB
import SendleMail
import SendlePersistence
import SendleUI

/// The only place that creates adapters. One store per file, shared by everything that uses it.
@MainActor
struct Composition {
  let panel: PanelModel
  private let settings: JSONSettingsStore

  /// Snapshot mode replaces every delivery, so that nothing is sent, and the plugged-in Kindles.
  init(
    loginItem: any LoginItem,
    channels override: (any DeliveryChannelFactory)? = nil,
    kindles: (any DestinationMonitor)? = nil
  ) {
    let data = DataDirectory.url()
    let settings = JSONSettingsStore(directory: data)
    let secrets = KeychainSecretStore()
    let staging = FileSystemStagingArea()
    let converter = CalibreConverter()
    let channels =
      override ?? DeliveryChannels(email: EmailChannelFactory(settings: settings, secrets: secrets))
    let configure = ConfigureEmail(settings: settings, secrets: secrets)
    let sendTest = SendTestEmail(settings: settings, channels: channels, staging: staging)
    let history = JSONSendHistoryStore(directory: data)
    let library = LibraryViewModel(
      loadLibrary: LoadLibrary(
        library: AppleBooksLibrary(location: .standard()), inspector: EPUBProtectionInspector()),
      observeDestinations: ObserveDestinations(
        monitor: kindles ?? KindleVolumeMonitor(), settings: settings),
      settings: settings,
      history: history,
      converter: converter)
    let setup = SetupViewModel(
      configure: configure, sendTest: sendTest,
      checkAccess: {
        await library.reload()
        return !library.needsAccess
      })
    panel = PanelModel(
      library: library, setup: setup,
      settings: SettingsViewModel(
        configure: configure, sendTest: sendTest, settings: settings, loginItem: loginItem),
      covers: CoverStore(provider: CachedCoverProvider()),
      queue: SendQueueViewModel(
        sendBooks: SendBooks(
          channels: channels, preparer: KindleEPUBPreparer(), converter: converter,
          staging: staging, history: history)),
      ejector: VolumeEjector())
    self.settings = settings
    // Clears folders an interrupted send left behind.
    staging.purge()
  }

  /// Loads the library and settings, and says so if the settings file had to be set aside.
  func launch() async {
    await panel.launch()
    if let moved = await settings.takeQuarantinedFile() {
      panel.show(notice: ProblemPresenter.settingsSetAside(moved))
    }
  }
}

/// Each destination's own adapter: SendleMail for email, SendleKindleUSB for a plugged-in Kindle.
struct DeliveryChannels: DeliveryChannelFactory {
  let email: EmailChannelFactory

  func channel(for destination: Destination) async throws(SendFailure) -> any DeliveryChannel {
    switch destination {
    case .email(let kindle): try await email.channel(to: kindle)
    case .usb(let volume): USBDeliveryChannel(volume: volume)
    }
  }
}
