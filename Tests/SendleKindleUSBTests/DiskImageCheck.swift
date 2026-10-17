import Foundation
import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing
import os

/// Plugs in a FAT disk image laid out like a Kindle, to check what fakes can't: NSWorkspace's
/// mount news, a real copy, a forced unmount mid-copy and Eject. It mounts volumes in Finder, so
/// it runs only with `SENDLE_DISK_IMAGE_CHECK=1`.
@Suite(
  .serialized, .timeLimit(.minutes(1)),
  .enabled(if: ProcessInfo.processInfo.environment["SENDLE_DISK_IMAGE_CHECK"] == "1"))
struct DiskImageCheck {
  @Test func followsAKindleFromPlugInToEject() async throws {
    let image = try DiskImage()
    defer { image.remove() }
    var updates = KindleVolumeMonitor().volumes().makeAsyncIterator()
    _ = await updates.next()

    let mountPoint = try image.attach()
    var kindle: KindleVolume?
    while kindle == nil, let list = await updates.next() {
      kindle = list.first { $0.mountURL.path == mountPoint.path }
    }
    let volume = try #require(kindle)
    #expect(volume.name == "SENDLETEST")

    let book = try makeTemporaryDirectory().appending(path: "book.pdf")
    try Data(repeating: 7, count: 300_000).write(to: book)
    try await USBDeliveryChannel(volume: volume).deliver(
      PreparedFile(url: book, format: .pdf), named: "Moby-Dick", progress: { _ in })
    let documents = mountPoint.appending(path: "documents")
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: documents.path) == ["Moby-Dick.pdf"])

    try await VolumeEjector().eject(volume)
    var isGone = false
    while !isGone, let list = await updates.next() {
      isGone = !list.contains(volume)
    }
    #expect(isGone)
  }

  @Test func aKindleUnmountedMidCopyWasUnplugged() async throws {
    let image = try DiskImage()
    defer { image.remove() }
    let mountPoint = try image.attach()
    let volume = KindleVolume(id: mountPoint.path, name: "SENDLETEST", mountURL: mountPoint)
    let book = try makeTemporaryDirectory().appending(path: "book.pdf")
    try Data(repeating: 7, count: 4_000_000).write(to: book)
    let channel = USBDeliveryChannel(volume: volume, chunkSize: 65_536, freeSpace: { _ in nil })

    await #expect(throws: SendFailure.deviceDisconnected) {
      try await channel.deliver(PreparedFile(url: book, format: .pdf), named: "Moby-Dick") { _ in
        image.yank()
      }
    }
  }

  @Test func ejectingAKindleInUseSaysSo() async throws {
    let image = try DiskImage()
    defer { image.remove() }
    let mountPoint = try image.attach()
    let volume = KindleVolume(id: mountPoint.path, name: "SENDLETEST", mountURL: mountPoint)
    let open = try FileHandle(
      forWritingTo: {
        let file = mountPoint.appending(path: "documents/open.txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        return file
      }())

    await #expect(throws: EjectError.inUse) { try await VolumeEjector().eject(volume) }

    try open.close()
    try await VolumeEjector().eject(volume)
  }
}

/// A 16 MB FAT disk image named SENDLETEST, with a Kindle's `documents` and `system` folders.
private final class DiskImage: Sendable {
  let file: URL
  private let mountPoints = OSAllocatedUnfairLock<[URL]>(initialState: [])

  init() throws {
    let folder = try makeTemporaryDirectory()
    let source = folder.appending(path: "root")
    for name in ["documents", "system"] {
      try FileManager.default.createDirectory(
        at: source.appending(path: name), withIntermediateDirectories: true)
    }
    file = folder.appending(path: "kindle.dmg")
    try Self.hdiutil([
      "create", "-quiet", "-srcfolder", source.path, "-fs", "MS-DOS", "-volname", "SENDLETEST",
      "-format", "UDRW", "-size", "16m", file.path,
    ])
  }

  /// Mounts it where Finder shows it, as a plugged-in Kindle is, and returns the mount point.
  func attach() throws -> URL {
    let plist = try Self.hdiutil(["attach", "-plist", file.path])
    let info = try PropertyListSerialization.propertyList(from: plist, format: nil)
    let entities = (info as? [String: Any])?["system-entities"] as? [[String: Any]] ?? []
    let path = try #require(entities.compactMap { $0["mount-point"] as? String }.first)
    let mountPoint = URL(filePath: path, directoryHint: .isDirectory)
    mountPoints.withLock { $0.append(mountPoint) }
    return mountPoint
  }

  /// Unmounts it even while files are open on it, as pulling the cable would.
  func yank() {
    for mountPoint in mountPoints.withLock({ $0 }) {
      _ = try? Self.hdiutil(["detach", "-quiet", "-force", mountPoint.path])
    }
  }

  func remove() {
    yank()
    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
  }

  @discardableResult
  private static func hdiutil(_ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/hdiutil")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw CocoaError(
        .fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "hdiutil \(arguments[0]) failed"])
    }
    return data
  }
}
