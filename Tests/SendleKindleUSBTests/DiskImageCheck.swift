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
    #expect(names(in: mountPoint.appending(path: "documents")) == ["Moby-Dick.pdf"])

    try await VolumeEjector().eject(volume)
    var isGone = false
    while !isGone, let list = await updates.next() {
      isGone = !list.contains(volume)
    }
    #expect(isGone)
  }

  @Test func leavesOnlyTheBookAndItsCoverOnTheKindle() async throws {
    let image = try DiskImage()
    defer { image.remove() }
    let mountPoint = try image.attach()
    let volume = KindleVolume(id: mountPoint.path, name: "SENDLETEST", mountURL: mountPoint)
    let book = try makeTemporaryDirectory().appending(path: "book.azw3")
    try makeAZW3(asin: "SN2Q7KXA4B", cover: makeJPEG(width: 80, height: 110)).write(to: book)

    try await USBDeliveryChannel(volume: volume).deliver(
      PreparedFile(url: book, format: .azw3), named: "Moby-Dick", progress: { _ in })

    #expect(names(in: mountPoint.appending(path: "documents")) == ["Moby-Dick.azw3"])
    #expect(
      names(in: mountPoint.appending(path: "system/thumbnails"))
        == ["thumbnail_SN2Q7KXA4B_EBOK_portrait.jpg"])
  }

  /// What a Kindle unplugged without Eject keeps is what reached it. FAT keeps a file's size and
  /// first cluster in its folder and the rest of its clusters in the FAT, so those must reach it.
  @Test func aBookIsOnTheKindleWhenTheSendEnds() async throws {
    let image = try DiskImage()
    defer { image.remove() }
    let mountPoint = try image.attach()
    let volume = KindleVolume(id: mountPoint.path, name: "SENDLETEST", mountURL: mountPoint)
    let book = try makeTemporaryDirectory().appending(path: "book.pdf")
    try Data(repeating: 7, count: 1_135_681).write(to: book)

    try await USBDeliveryChannel(volume: volume).deliver(
      PreparedFile(url: book, format: .pdf), named: "BOOK", progress: { _ in })

    let device = try #require(FATVolume(image: Data(contentsOf: image.file)))
    let entry = try #require(device.entry(shortName: "BOOK    PDF"))
    #expect(entry.size == 1_135_681)
    #expect(entry.clusters == (1_135_681 + device.clusterSize - 1) / device.clusterSize)
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

/// Every name in `folder`, as the Kindle sees them. FileManager leaves out the `._` files macOS
/// keeps extended attributes in on FAT.
private func names(in folder: URL) -> [String] {
  guard let directory = opendir(folder.path) else { return [] }
  defer { closedir(directory) }
  var names: [String] = []
  while let entry = readdir(directory) {
    let name = withUnsafeBytes(of: entry.pointee.d_name) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    if name != ".", name != ".." { names.append(name) }
  }
  return names.sorted()
}

/// A FAT volume read straight from its disk image, as a Kindle unplugged now would find it.
private struct FATVolume {
  struct Entry {
    var size: Int
    var clusters: Int
  }

  let bytes: [UInt8]
  let clusterSize: Int
  private let fat: [UInt8]
  private let isFAT32: Bool

  init?(image: Data) {
    let whole = [UInt8](image)
    guard whole.count > 512 else { return nil }
    // `hdiutil create` puts the volume in an MBR partition.
    let isBootSector =
      whole[54..<57].elementsEqual("FAT".utf8) || whole[82..<85].elementsEqual("FAT".utf8)
    let start = isBootSector ? 0 : Int(Self.little(whole, 446 + 8, 4)) * 512
    bytes = Array(whole[start...])
    let sectorSize = Int(Self.little(bytes, 11, 2))
    clusterSize = sectorSize * Int(bytes[13])
    let reserved = Int(Self.little(bytes, 14, 2))
    let fatSectors16 = Int(Self.little(bytes, 22, 2))
    isFAT32 = fatSectors16 == 0
    let fatSectors = isFAT32 ? Int(Self.little(bytes, 36, 4)) : fatSectors16
    fat = Array(bytes[(reserved * sectorSize)..<((reserved + fatSectors) * sectorSize)])
  }

  /// The live folder entry with `shortName` (8.3, space-padded), and the length of its chain.
  func entry(shortName: String) -> Entry? {
    let name = Array(shortName.utf8)
    var found: Entry?
    for offset in stride(from: 0, to: bytes.count - 32, by: 32)
    where bytes[offset] != 0xE5 && bytes[offset..<(offset + 11)].elementsEqual(name) {
      var cluster = Int(
        Self.little(bytes, offset + 26, 2) | Self.little(bytes, offset + 20, 2) << 16)
      var clusters = 0
      while cluster >= 2, cluster < (isFAT32 ? 0x0FFF_FFF8 : 0xFFF8), clusters < 1_000_000 {
        clusters += 1
        cluster =
          isFAT32
          ? Int(Self.little(fat, cluster * 4, 4) & 0x0FFF_FFFF)
          : Int(Self.little(fat, cluster * 2, 2))
      }
      found = Entry(size: Int(Self.little(bytes, offset + 28, 4)), clusters: clusters)
    }
    return found
  }

  /// The little-endian number of `count` bytes at `offset`.
  private static func little(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> UInt32 {
    bytes[offset..<(offset + count)].reversed().reduce(0) { $0 << 8 | UInt32($1) }
  }
}

/// A 16 MB FAT disk image named SENDLETEST/// A 16 MB FAT disk image named SENDLETEST, with a Kindle's `documents` and `system` folders.
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
