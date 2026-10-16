import Foundation
import SendleAppleBooks
import SendleCovers
import SendleDomain
import SendleEPUB
import SendlePersistence
import SendleUI

/// The only place that creates adapters. One store per file, shared by everything that uses it.
@MainActor
struct Composition {
  let panel: PanelModel
  private let settings: JSONSettingsStore

  init(loginItem: any LoginItem) {
    let data = DataDirectory.url()
    let settings = JSONSettingsStore(directory: data)
    let configure = ConfigureEmail(settings: settings, secrets: KeychainSecretStore())
    let library = LibraryViewModel(
      loadLibrary: LoadLibrary(
        library: AppleBooksLibrary(location: .standard()), inspector: EPUBProtectionInspector()),
      observeDestinations: ObserveDestinations(monitor: NoKindleMonitor(), settings: settings),
      settings: settings,
      history: JSONSendHistoryStore(directory: data))
    let setup = SetupViewModel(
      configure: configure,
      checkAccess: {
        await library.reload()
        return !library.needsAccess
      })
    panel = PanelModel(
      library: library, setup: setup,
      settings: SettingsViewModel(configure: configure, settings: settings, loginItem: loginItem),
      covers: CoverStore(provider: CachedCoverProvider()))
    self.settings = settings
    // Clears folders an interrupted send left behind.
    FileSystemStagingArea().purge()
  }

  /// Loads the library and settings, and says so if the settings file had to be set aside.
  func launch() async {
    await panel.launch()
    if let moved = await settings.takeQuarantinedFile() {
      panel.show(notice: ProblemPresenter.settingsSetAside(moved))
    }
  }
}

/// No Kindle is ever plugged in until USB support arrives.
struct NoKindleMonitor: DestinationMonitor {
  func volumes() -> AsyncStream<[KindleVolume]> {
    AsyncStream { $0.yield([]) }
  }
}
