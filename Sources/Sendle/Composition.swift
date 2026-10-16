import Foundation
import SendleAppleBooks
import SendleCovers
import SendleDomain
import SendleEPUB
import SendleMail
import SendlePersistence
import SendleUI

/// The only place that creates adapters. One store per file, shared by everything that uses it.
@MainActor
struct Composition {
  let panel: PanelModel
  private let settings: JSONSettingsStore

  /// `channels` replaces email delivery, as snapshot mode does so that nothing is sent.
  init(loginItem: any LoginItem, channels override: (any DeliveryChannelFactory)? = nil) {
    let data = DataDirectory.url()
    let settings = JSONSettingsStore(directory: data)
    let secrets = KeychainSecretStore()
    let staging = FileSystemStagingArea()
    let channels =
      override ?? DeliveryChannels(email: EmailChannelFactory(settings: settings, secrets: secrets))
    let configure = ConfigureEmail(settings: settings, secrets: secrets)
    let sendTest = SendTestEmail(settings: settings, channels: channels, staging: staging)
    let history = JSONSendHistoryStore(directory: data)
    let library = LibraryViewModel(
      loadLibrary: LoadLibrary(
        library: AppleBooksLibrary(location: .standard()), inspector: EPUBProtectionInspector()),
      observeDestinations: ObserveDestinations(monitor: NoKindleMonitor(), settings: settings),
      settings: settings,
      history: history)
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
          channels: channels, preparer: KindleEPUBPreparer(), converter: NoConverter(),
          staging: staging, history: history)))
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

/// Email goes through SendleMail. USB arrives with Plan 5; until then no Kindle is ever offered.
struct DeliveryChannels: DeliveryChannelFactory {
  let email: EmailChannelFactory

  func channel(for destination: Destination) async throws(SendFailure) -> any DeliveryChannel {
    switch destination {
    case .email(let kindle): try await email.channel(to: kindle)
    case .usb: throw .deviceDisconnected
    }
  }
}

/// Calibre support arrives with USB, so EPUBs only go by email for now.
struct NoConverter: FormatConverter {
  let isAvailable = false

  func convert(
    _ file: PreparedFile,
    to format: FileFormat,
    in staging: URL
  ) async throws(SendFailure) -> PreparedFile {
    throw .conversionUnavailable
  }
}

/// No Kindle is ever plugged in until USB support arrives.
struct NoKindleMonitor: DestinationMonitor {
  func volumes() -> AsyncStream<[KindleVolume]> {
    AsyncStream { $0.yield([]) }
  }
}
