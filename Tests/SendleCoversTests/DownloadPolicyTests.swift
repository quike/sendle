import Darwin
import SendleCovers
import Testing

struct DownloadPolicyTests {
  @Test func turnsDownloadsOffOnlyWhileTheBodyRuns() {
    let policy = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
    let before = getiopolicy_np(policy, IOPOL_SCOPE_THREAD)

    let inside = withoutDownloads { getiopolicy_np(policy, IOPOL_SCOPE_THREAD) }

    #expect(inside == IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
    #expect(getiopolicy_np(policy, IOPOL_SCOPE_THREAD) == before)
  }
}
