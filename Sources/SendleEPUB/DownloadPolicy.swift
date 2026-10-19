import Darwin

/// Runs `body` with iCloud downloads off for this thread, so reading a placeholder fails instead
/// of fetching the book. Nil when the policy can't be set. `body` must not suspend.
package func withoutDownloads<T>(_ body: () -> T?) -> T? {
  let policy = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
  let previous = getiopolicy_np(policy, IOPOL_SCOPE_THREAD)
  guard previous >= 0,
    setiopolicy_np(policy, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0
  else { return nil }
  defer { setiopolicy_np(policy, IOPOL_SCOPE_THREAD, previous) }
  return body()
}
