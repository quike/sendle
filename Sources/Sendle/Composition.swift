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
  private let chooseTool: ChooseConverterTool

  /// Snapshot mode replaces every delivery, so that nothing is sent, the plugged-in Kindles, how
  /// they are read and what removes a book from them.
  init(
    loginItem: any LoginItem,
    channels override: (any DeliveryChannelFactory)? = nil,
    kindles: (any DestinationMonitor)? = nil,
    kindleLibrary: (any KindleLibrary)? = nil,
    remover: (any KindleBookRemover)? = nil
  ) {
    let data = DataDirectory.url()
    let log = MemoryActivityLog()
    let settings = JSONSettingsStore(directory: data, log: log)
    let secrets = KeychainSecretStore()
    let staging = FileSystemStagingArea()
    let converter = BokoConverter(log: log)
    let channels =
      override
      ?? DeliveryChannels(
        email: EmailChannelFactory(settings: settings, secrets: secrets, log: log), log: log)
    let configure = ConfigureEmail(settings: settings, secrets: secrets, log: log)
    let sendTest = SendTestEmail(
      settings: settings, channels: channels, staging: staging, log: log)
    let history = JSONSendHistoryStore(directory: data, log: log)
    let edits = JSONMetadataEditStore(directory: data, log: log)
    let hiddenBooks = JSONHiddenBooksStore(directory: data, log: log)
    let chooseTool = ChooseConverterTool(settings: settings, choice: converter, log: log)
    // One instance, so a Replace's removal and a delete's leftovers sweep know each other's holds.
    let remover = remover ?? USBKindleBookRemover(log: log)
    let library = LibraryViewModel(
      loadLibrary: LoadLibrary(
        library: AppleBooksLibrary(location: .standard()), inspector: EPUBProtectionInspector(),
        edits: edits, settings: settings, log: log),
      observeDestinations: ObserveDestinations(
        monitor: kindles ?? KindleVolumeMonitor(log: log), settings: settings),
      settings: settings,
      history: history,
      converter: converter,
      hiddenBooks: hiddenBooks)
    let kindle = KindleViewModel(
      library: kindleLibrary ?? USBKindleLibrary(cacheDirectory: data, log: log),
      match: MatchKindleBooks(
        editions: OPFEditionReader(cacheFile: data.appending(path: "editions.json")),
        digests: CachedFileDigester(), kindleDigests: CachedKindleDigester(cacheDirectory: data),
        asins: SendleASINScheme(), history: history),
      canReplaceOtherCopies: true)
    let setup = SetupViewModel(
      configure: configure, sendTest: sendTest,
      checkAccess: {
        await library.reload()
        return !library.needsAccess
      })
    panel = PanelModel(
      library: library, setup: setup,
      settings: SettingsViewModel(
        configure: configure, sendTest: sendTest,
        addresses: ManageKindleAddresses(settings: settings, log: log), chooseTool: chooseTool,
        settings: settings, loginItem: loginItem, converter: converter, log: log),
      covers: CoverStore(provider: CachedCoverProvider()),
      queue: SendQueueViewModel(
        sendBooks: SendBooks(
          channels: channels, preparer: KindleEPUBPreparer(log: log), converter: converter,
          staging: staging, history: history, settings: settings, remover: remover,
          asins: SendleASINScheme(), log: log)),
      logs: LogsViewModel(feed: log), kindle: kindle,
      editDetails: EditBookDetails(store: edits, settings: settings),
      ejector: VolumeEjector(log: log),
      removal: KindleRemovalModel(removals: KindleRemovals(remover: remover, log: log)), log: log)
    self.settings = settings
    self.chooseTool = chooseTool
    // Clears folders an interrupted send left behind.
    staging.purge()
  }

  /// Loads the library and settings, and says so if the settings file had to be set aside.
  func launch() async {
    await chooseTool.restore()
    await panel.launch()
    if let moved = await settings.takeQuarantinedFile() {
      panel.show(notice: ProblemPresenter.settingsSetAside(moved))
    }
  }
}

/// Each destination's own adapter: SendleMail for email, SendleKindleUSB for a plugged-in Kindle.
struct DeliveryChannels: DeliveryChannelFactory {
  let email: EmailChannelFactory
  let log: any ActivityLog

  func channel(for destination: Destination) async throws(SendFailure) -> any DeliveryChannel {
    switch destination {
    case .email(let kindle): try await email.channel(to: kindle)
    case .usb(let volume): USBDeliveryChannel(volume: volume, log: log)
    }
  }
}
