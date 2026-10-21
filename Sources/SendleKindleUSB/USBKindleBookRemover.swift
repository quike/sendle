import Darwin
import Foundation
import SendleDomain

/// Deletes a book from a drive-mounted Kindle in two steps. `hold` renames the book's own files
/// into `<root>/.sendle-held/<id>/` under names the Kindle doesn't list; `restore` renames them
/// back, and `finalize` removes them and the folders they leave empty. Nothing is copied.
public actor USBKindleBookRemover: KindleBookRemover {
  package typealias Flush = @Sendable (URL) -> Void

  package static let holdingFolder = ".sendle-held"

  /// A rename, with both paths relative to the Kindle's root.
  private struct Move {
    let from: String
    let to: String

    var reversed: Move { Move(from: to, to: from) }
  }

  private struct Hold {
    let moves: [Move]
    let emptyFolders: [String]
    let root: URL
  }

  private static let keys: Set<URLResourceKey> = [
    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
  ]

  private let log: any ActivityLog
  private let flush: Flush
  private var holds: [UUID: Hold] = [:]

  public init(log: any ActivityLog = NoActivityLog()) {
    self.init(log: log, flush: { DeviceSync.flush($0) })
  }

  package init(log: any ActivityLog, flush: @escaping Flush) {
    self.log = log
    self.flush = flush
  }

  public func hold(_ book: KindleBook, listedWith listing: [KindleBook], on volume: KindleVolume)
    async throws(KindleRemovalError) -> HeldBook
  {
    let root = volume.mountURL
    let path = "documents/\(book.id.relativePath)"
    guard Self.isFolder(root.appending(path: "documents")) else { throw .deviceDisconnected }
    try Self.check(book, at: path, in: root, listedWith: listing)
    let siblings = try Self.names(in: Self.parent(of: path), root: root)
    guard
      let plan = RemovalPlan.make(
        for: book, listing: listing, siblings: Set(siblings),
        thumbnailExists: { Self.exists($0, in: root) }),
      plan.parts.allSatisfy({ Self.blockedFolder(above: $0.path, in: root) == nil })
    else { throw .failed("Sendle won't delete \(path)") }

    let id = UUID()
    let folder = "\(Self.holdingFolder)/\(id.uuidString)"
    try Self.makeHoldingFolder(folder, in: root)
    var moved: [Move] = []
    var parts: [HeldPart] = []
    defer {
      flush(moved.map { Self.parent(of: $0.from) } + [folder, Self.holdingFolder], in: root)
    }
    for part in plan.parts {
      let move = Move(from: part.path, to: "\(folder)/\(moved.count).held")
      guard Self.rename(move, in: root) else {
        let code = errno
        // Only the book must be there. On FAT, macOS moves a "._" twin along with its file.
        if part != .book(part.path), code == ENOENT, Self.isMissing(part.path, in: root) {
          continue
        }
        putBack(moved, in: root)
        Self.removeIfEmpty([folder, Self.holdingFolder], in: root)
        throw Self.failure(code, root: root)
      }
      moved.append(move)
      if let kind = Self.heldPart(part) { parts.append(kind) }
    }
    holds[id] = Hold(moves: moved, emptyFolders: plan.emptyFolders, root: root)
    return HeldBook(id: id, book: book, volume: volume, parts: parts)
  }

  public func restore(_ held: HeldBook) async throws(KindleRemovalError) {
    guard let hold = holds[held.id] else { throw .failed("Sendle no longer holds it") }
    let root = hold.root
    guard Self.isFolder(root.appending(path: "documents")) else { throw .deviceDisconnected }
    let moves = hold.moves.reversed().map(\.reversed)
    for move in moves {
      if Self.exists(move.to, in: root) { throw .occupied(move.to) }
      if let blocked = Self.blockedFolder(above: move.to, in: root) { throw .occupied(blocked) }
    }
    var made: [String] = []
    var moved: [Move] = []
    defer {
      let folders = (moved.map(\.to) + made).map(Self.parent(of:))
      flush(folders + [Self.holdingFolder], in: root)
    }
    for move in moves { made += try Self.makeFolders(above: move.to, in: root) }
    for move in moves {
      guard Self.rename(move, in: root) else {
        let code = errno
        putBack(moved, in: root)
        throw Self.failure(code, root: root)
      }
      moved.append(move)
    }
    holds[held.id] = nil
    Self.removeIfEmpty(
      ["\(Self.holdingFolder)/\(held.id.uuidString)", Self.holdingFolder], in: root)
  }

  /// A hold it fails to remove is forgotten, so the next `clearLeftovers` removes it.
  public func finalize(_ held: HeldBook) async throws(KindleRemovalError) {
    guard let hold = holds.removeValue(forKey: held.id) else { return }
    let root = hold.root
    guard Self.isFolder(root.appending(path: "documents")) else { throw .deviceDisconnected }
    let folder = "\(Self.holdingFolder)/\(held.id.uuidString)"
    defer {
      let parents = hold.emptyFolders.map(Self.parent(of:))
      flush(parents + ["documents", Self.holdingFolder], in: root)
    }
    guard Self.blockedFolder(above: folder, in: root) == nil else {
      throw .failed("\(Self.holdingFolder) isn't a folder")
    }
    guard Self.removeAll(root.appending(path: folder)) || errno == ENOENT else {
      throw Self.failure(errno, root: root)
    }
    for empty in hold.emptyFolders where Self.blockedFolder(above: empty, in: root) == nil {
      guard rmdir(root.appending(path: empty).path) != 0 else { continue }
      let code = errno
      if code != ENOTEMPTY, code != ENOENT {
        log.warning(.usb, "Couldn't remove the empty folder \(empty): \(Self.reason(code))")
      }
    }
    Self.removeIfEmpty([Self.holdingFolder], in: root)
  }

  public func clearLeftovers(on volume: KindleVolume) async -> Int {
    let root = volume.mountURL
    guard Self.kind(of: root.appending(path: Self.holdingFolder)) == S_IFDIR,
      let names = try? Self.names(in: Self.holdingFolder, root: root)
    else { return 0 }
    let held = Set(holds.keys.map(\.uuidString))
    var cleared = 0
    // macOS keeps a "._" file for the entry it names on FAT, and removes it with that entry.
    for name in names where !name.hasPrefix("._") && !held.contains(name) {
      let path = "\(Self.holdingFolder)/\(name)"
      if Self.removeAll(root.appending(path: path)) {
        cleared += 1
      } else {
        log.warning(.usb, "Couldn't clear \(path): \(Self.reason(errno))")
      }
    }
    Self.removeIfEmpty([Self.holdingFolder], in: root)
    if cleared > 0 || !Self.exists(Self.holdingFolder, in: root) {
      flush([Self.holdingFolder], in: root)
    }
    return cleared
  }

  // MARK: Private

  /// The book must be the regular file the listing read: same size, same date.
  private static func check(
    _ book: KindleBook, at path: String, in root: URL, listedWith listing: [KindleBook]
  ) throws(KindleRemovalError) {
    guard let values = try? root.appending(path: path).resourceValues(forKeys: keys) else {
      throw isFolder(root.appending(path: "documents")) ? .changedSinceListed : .deviceDisconnected
    }
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw .failed("\(path) isn't a book file")
    }
    let size = Int64(values.fileSize ?? 0)
    let modified = values.contentModificationDate ?? .distantPast
    let copies = [book] + listing.filter { $0.id == book.id }
    guard copies.allSatisfy({ $0.byteCount == size && $0.modified == modified }) else {
      throw .changedSinceListed
    }
  }

  private static func makeHoldingFolder(_ folder: String, in root: URL) throws(KindleRemovalError) {
    if mkdir(root.appending(path: holdingFolder).path, 0o755) != 0, errno != EEXIST {
      throw failure(errno, root: root)
    }
    guard kind(of: root.appending(path: holdingFolder)) == S_IFDIR else {
      throw .failed("\(holdingFolder) isn't a folder")
    }
    guard mkdir(root.appending(path: folder).path, 0o755) == 0 else {
      let code = errno
      removeIfEmpty([holdingFolder], in: root)
      throw failure(code, root: root)
    }
  }

  /// Renames each of `moves` back, last first. One that can't go back stays where it is.
  private func putBack(_ moves: [Move], in root: URL) {
    for move in moves.reversed().map(\.reversed) where !Self.rename(move, in: root) {
      log.warning(.usb, "Couldn't move \(move.from) back to \(move.to): \(Self.reason(errno))")
    }
  }

  private static func isMissing(_ path: String, in root: URL) -> Bool {
    !Self.exists(path, in: root) && Self.isFolder(root.appending(path: "documents"))
  }

  private func flush(_ folders: [String], in root: URL) {
    for folder in Set(folders + [""]) {
      flush(folder.isEmpty ? root : root.appending(path: folder))
    }
  }

  private static func rename(_ move: Move, in root: URL) -> Bool {
    Darwin.rename(root.appending(path: move.from).path, root.appending(path: move.to).path) == 0
  }

  /// Creates the missing folders on the way down to `path`, and returns them.
  private static func makeFolders(above path: String, in root: URL) throws(KindleRemovalError)
    -> [String]
  {
    var made: [String] = []
    for folder in folders(above: path) {
      if mkdir(root.appending(path: folder).path, 0o755) == 0 {
        made.append(folder)
      } else if errno != EEXIST {
        throw failure(errno, root: root)
      }
    }
    return made
  }

  /// The first folder on the way down to `path` that is something else, such as a link.
  private static func blockedFolder(above path: String, in root: URL) -> String? {
    for folder in folders(above: path) {
      guard let kind = kind(of: root.appending(path: folder)) else { return nil }
      if kind != S_IFDIR { return folder }
    }
    return nil
  }

  /// "a", "a/b" for "a/b/c".
  private static func folders(above path: String) -> [String] {
    let components = path.split(separator: "/").dropLast()
    return components.indices.map { components[...$0].joined(separator: "/") }
  }

  private static func parent(of path: String) -> String {
    path.split(separator: "/").dropLast().joined(separator: "/")
  }

  private static func names(in folder: String, root: URL) throws(KindleRemovalError) -> [String] {
    guard let directory = opendir(root.appending(path: folder).path) else {
      throw failure(errno, root: root)
    }
    defer { closedir(directory) }
    var names: [String] = []
    while let entry = readdir(directory) {
      let name = withUnsafeBytes(of: entry.pointee.d_name) {
        String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
      }
      if name != ".", name != ".." { names.append(name) }
    }
    return names
  }

  private static func heldPart(_ part: RemovalPlan.Part) -> HeldPart? {
    switch part {
    case .book: .book
    case .sidecar: .sidecar
    case .thumbnail: .cover
    case .appleDouble, .thumbnailAppleDouble: nil
    }
  }

  private static func removeIfEmpty(_ folders: [String], in root: URL) {
    for folder in folders { rmdir(root.appending(path: folder).path) }
  }

  /// Removes a file, or a folder and all it holds, without following links.
  private static func removeAll(_ url: URL) -> Bool {
    removefile(url.path, nil, removefile_flags_t(REMOVEFILE_RECURSIVE)) == 0
  }

  private static func exists(_ path: String, in root: URL) -> Bool {
    kind(of: root.appending(path: path)) != nil
  }

  /// The file type bits of what is at `url`, without following a link.
  private static func kind(of url: URL) -> mode_t? {
    var info = stat()
    return lstat(url.path, &info) == 0 ? info.st_mode & S_IFMT : nil
  }

  private static func isFolder(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func failure(_ code: Int32, root: URL) -> KindleRemovalError {
    let mounted = isFolder(root.appending(path: "documents"))
    switch USBDeliveryChannel.failure(errno: code, volumeIsMounted: mounted) {
    case .deviceDisconnected: return .deviceDisconnected
    case .diskFull: return .failed("the Kindle is full")
    case .copyFailed(let reason): return .failed(reason)
    default: return .failed(reason(code))
    }
  }

  private static func reason(_ code: Int32) -> String {
    String(cString: strerror(code))
  }
}
