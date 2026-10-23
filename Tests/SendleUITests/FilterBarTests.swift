import AppKit
import SendleDomain
import SendleTestSupport
import SendleUI
import SwiftUI
import Testing

@MainActor
struct FilterBarTests {
  /// The row inside the panel: Theme.cardSize's 400 pt less the screen's 14 pt padding on each side.
  let contentWidth: CGFloat = 400 - 28

  func idealWidth(withKindle: Bool) async -> CGFloat {
    let settings = InMemorySettingsStore(AppSettings(email: .fixture))
    let model = LibraryViewModel(
      loadLibrary: LoadLibrary(
        library: FakeBooksLibrary(.success([])), inspector: StubProtectionInspector()),
      observeDestinations: ObserveDestinations(
        monitor: FakeDestinationMonitor(), settings: settings),
      settings: settings, history: InMemorySendHistoryStore(),
      converter: FakeFormatConverter(isAvailable: false))
    await model.start()
    if withKindle { model.showKindleMatches(.empty) }
    return NSHostingView(rootView: FilterBar(library: model)).fittingSize.width
  }

  @Test func theBarFitsTheContentWidthBeforeAKindleAddsScopes() async {
    #expect(await idealWidth(withKindle: false) <= contentWidth)
  }

  @Test func allFourLibraryScopesFitTheContentWidth() async {
    #expect(await idealWidth(withKindle: true) <= contentWidth)
  }
}
