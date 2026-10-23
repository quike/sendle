import Foundation

/// Watches a folder, and the library files in it, for writes. Reports bursts of changes once,
/// `batchDelay` after the first one. All mutable state lives on `queue`.
package final class LibraryWatcher: @unchecked Sendable {
  private let directory: URL
  private let isLibraryFile: @Sendable (String) -> Bool
  private let batchDelay: DispatchTimeInterval
  private let onChange: @Sendable () -> Void
  private let queue = DispatchQueue(label: "io.github.quike.Sendle.library-watcher")
  private var directorySource: (any DispatchSourceFileSystemObject)?
  private var fileSources: [String: any DispatchSourceFileSystemObject] = [:]
  private var isBatching = false
  private var isStopped = false

  /// `onChange` runs on the watcher's private queue, so it must not call `start()`.
  package init(
    directory: URL,
    isLibraryFile: @escaping @Sendable (String) -> Bool,
    batchDelay: DispatchTimeInterval,
    onChange: @escaping @Sendable () -> Void
  ) {
    self.directory = directory
    self.isLibraryFile = isLibraryFile
    self.batchDelay = batchDelay
    self.onChange = onChange
  }

  /// False when the folder can't be watched, e.g. because it's missing or unreadable.
  package func start() -> Bool {
    queue.sync {
      directorySource = watch(directory, events: .write) { [weak self] _ in
        self?.refreshFileSources()
        self?.scheduleChange()
      }
      guard directorySource != nil else { return false }
      refreshFileSources()
      return true
    }
  }

  /// Cancels every source. An `onChange` that is already due may still run once.
  package func stop() {
    queue.async { [self] in
      isStopped = true
      directorySource?.cancel()
      directorySource = nil
      fileSources.values.forEach { $0.cancel() }
      fileSources.removeAll()
    }
  }

  private func refreshFileSources() {
    let names =
      (try? FileManager.default.contentsOfDirectory(
        atPath: directory.path(percentEncoded: false))) ?? []
    let wanted = Set(names.filter(isLibraryFile))
    for (name, source) in fileSources where !wanted.contains(name) {
      source.cancel()
      fileSources[name] = nil
    }
    for name in wanted where fileSources[name] == nil {
      fileSources[name] = watch(
        directory.appending(path: name), events: [.write, .extend, .delete, .rename]
      ) { [weak self] events in
        self?.fileChanged(name, events)
      }
    }
  }

  private func fileChanged(_ name: String, _ events: DispatchSource.FileSystemEvent) {
    if !events.isDisjoint(with: [.delete, .rename]) {
      fileSources.removeValue(forKey: name)?.cancel()
      refreshFileSources()
    }
    scheduleChange()
  }

  private func scheduleChange() {
    guard !isBatching, !isStopped else { return }
    isBatching = true
    queue.asyncAfter(deadline: .now() + batchDelay) { [weak self] in
      guard let self, !isStopped else { return }
      isBatching = false
      onChange()
    }
  }

  private func watch(
    _ url: URL,
    events: DispatchSource.FileSystemEvent,
    handler: @escaping (DispatchSource.FileSystemEvent) -> Void
  ) -> (any DispatchSourceFileSystemObject)? {
    let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
    guard descriptor >= 0 else { return nil }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: events, queue: queue)
    source.setEventHandler { [weak source] in
      guard let source else { return }
      handler(source.data)
    }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    return source
  }
}
