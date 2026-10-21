import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI

@MainActor
final class FakeSystemActions: SystemActions {
  var opened: [URL] = []
  var revealedApp = 0
  var closedPanel = 0
  var endedEditing = 0
  var program: URL?
  var image: URL?
  var copied: [String] = []

  func open(_ url: URL) { opened.append(url) }
  func revealApp() { revealedApp += 1 }
  func closePanel() { closedPanel += 1 }
  func endEditing() { endedEditing += 1 }
  func chooseProgram() async -> URL? { program }
  func chooseImage() async -> URL? { image }
  func copy(_ text: String) { copied.append(text) }
}

/// The panel with fakes behind it, for the suites that drive it.
@MainActor
struct PanelHarness {
  let library = FakeBooksLibrary(.success([.fixture(id: "a"), .fixture(id: "b")]))
  let monitor = FakeDestinationMonitor()
  let system = FakeSystemActions()
  let history = InMemorySendHistoryStore()
  let ejector = FakeKindleEjector()
  let log = FakeActivityLog()

  /// `onSleep` runs each time setup waits between access checks.
  /// `channel` delivers every send and test email; `ejector` replaces the harness's.
  /// `edits` apply to the library's books, and `editions` are their EPUBs' editions. Saving a book's
  /// details fails with `editFailure`. `remover` removes the copy a Replace leaves behind, and
  /// turns Replace on for copies Sendle did not name.
  func makePanel(
    _ saved: AppSettings = AppSettings(email: .fixture),
    channel: FakeDeliveryChannel = FakeDeliveryChannel(),
    ejector: FakeKindleEjector? = nil,
    kindle: FakeKindleLibrary = FakeKindleLibrary(),
    converter: FakeFormatConverter = FakeFormatConverter(isAvailable: false),
    edits: MetadataEdits = .none,
    editions: [BookID: Edition] = [:],
    editFailure: MetadataEditError? = nil,
    remover: FakeKindleBookRemover? = nil,
    onSleep: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: .seconds(60)) }
  ) -> (PanelModel, InMemorySettingsStore) {
    let settings = InMemorySettingsStore(saved)
    let editStore = InMemoryMetadataEditStore(edits, failure: editFailure)
    let configure = ConfigureEmail(settings: settings, secrets: MemorySecretStore())
    let channels = FakeDeliveryChannelFactory(channel: channel)
    let staging = FakeStagingArea()
    let sendTest = SendTestEmail(settings: settings, channels: channels, staging: staging)
    let libraryModel = LibraryViewModel(
      loadLibrary: LoadLibrary(
        library: library, inspector: StubProtectionInspector(), edits: editStore,
        settings: settings),
      observeDestinations: ObserveDestinations(monitor: monitor, settings: settings),
      settings: settings, history: history, converter: converter)
    let setup = SetupViewModel(
      configure: configure, sendTest: sendTest,
      checkAccess: {
        await libraryModel.reload()
        return !libraryModel.needsAccess
      },
      sleep: { _ in await onSleep() })
    let panel = PanelModel(
      library: libraryModel, setup: setup,
      settings: SettingsViewModel(
        configure: configure, sendTest: sendTest,
        addresses: ManageKindleAddresses(settings: settings),
        chooseTool: ChooseConverterTool(
          settings: settings, choice: converter, isExecutable: { _ in true }),
        settings: settings, loginItem: FakeLoginItem(), converter: converter),
      covers: CoverStore(provider: FakeCoverProvider()),
      queue: SendQueueViewModel(
        sendBooks: SendBooks(
          channels: channels, preparer: FakeEPUBPreparer(editions: editions), converter: converter,
          staging: staging, history: history,
          retryDelay: .zero, sleep: { _ in }, remover: remover)),
      logs: LogsViewModel(feed: log),
      kindle: makeKindleModel(
        reading: kindle, history: history, editions: editions,
        canReplaceOtherCopies: remover != nil),
      editDetails: EditBookDetails(store: editStore, settings: settings),
      ejector: ejector ?? self.ejector, log: log)
    panel.attach(system)
    return (panel, settings)
  }

  /// A library of two PDFs unless `books` says otherwise, a Kindle holding `listing`, USB as the
  /// destination, and the Kindle read. `converts` lets EPUBs go over USB.
  func pluggedInPanel(
    listing: [KindleBook], books: [Book]? = nil, converts: Bool = false,
    edits: MetadataEdits = .none, editions: [BookID: Edition] = [:],
    remover: FakeKindleBookRemover? = nil
  ) async -> (panel: PanelModel, kindle: FakeKindleLibrary, channel: FakeDeliveryChannel) {
    library.result = .success(
      books ?? [
        .fixture(id: "a", format: .pdf),
        .fixture(id: "b", title: "Dracula", author: "Bram Stoker", format: .pdf),
      ])
    let kindle = FakeKindleLibrary(.success(.fixture(listing)))
    let channel = FakeDeliveryChannel()
    let (panel, _) = makePanel(
      AppSettings(email: .fixture, activeDestination: .usb), channel: channel, kindle: kindle,
      converter: FakeFormatConverter(isAvailable: converts), edits: edits, editions: editions,
      remover: remover)
    monitor.update([.fixture()])
    await panel.launch()
    await panel.panelDidOpen()
    _ = await eventually {
      panel.library.activeDestination == .usb(.fixture()) && panel.kindle.state == .loaded
        && panel.kindle.matches != nil
    }
    return (panel, kindle, channel)
  }

  func denyAccess() {
    library.result = .failure(.accessDenied)
    library.canWatch = false
  }

  func grantAccess() {
    library.result = .success([.fixture(id: "a")])
    library.canWatch = true
  }
}
