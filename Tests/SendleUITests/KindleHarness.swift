import SendleDomain
import SendleTestSupport
import SendleUI

/// A Kindle view model whose matching reads nothing from disk.
@MainActor
func makeKindleModel(
  reading library: any KindleLibrary = FakeKindleLibrary(),
  history: any SendHistoryStore = InMemorySendHistoryStore()
) -> KindleViewModel {
  KindleViewModel(
    library: library,
    match: MatchKindleBooks(
      editions: FakeEditionReader(), digests: FakeFileDigester(), asins: FakeASINScheme(),
      history: history))
}
