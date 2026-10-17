import Foundation
import SendleKindleUSB
import Testing

struct KindleVolumeDetectorTests {
  @Test(
    arguments: [
      (["documents", "system"], "Kindle", true),
      (["documents", "system"], "Paperwhite", true),
      (["documents", "audible", "fonts"], "KINDLE", true),
      (["documents"], "USB DRIVE", false),
      (["system"], "Kindle", false),
      (["Documents", "System"], "Backup", false),
      ([], "Kindle", false),
    ] as [([String], String, Bool)])
  func recognisesAKindleByItsFolders(folders: [String], name: String, isKindle: Bool) throws {
    let root = try makeVolumeRoot(folders: folders)
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(KindleVolumeDetector.isKindle(root: root, name: name) == isKindle)
  }

  @Test func ignoresFilesNamedLikeItsFolders() throws {
    let root = try makeVolumeRoot(folders: [])
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appending(path: "documents"))
    try Data().write(to: root.appending(path: "system"))

    #expect(!KindleVolumeDetector.isKindle(root: root, name: "Kindle"))
  }

  @Test func aVolumeThatIsGoneIsNotAKindle() {
    let gone = URL(filePath: "/Volumes/Sendle-\(UUID().uuidString)", directoryHint: .isDirectory)

    #expect(!KindleVolumeDetector.isKindle(root: gone, name: "Kindle"))
  }
}
