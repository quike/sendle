import Foundation
import SendleDomain
import SendleTestSupport
import Testing

struct ChooseConverterToolTests {
  let tool = URL(filePath: "/Users/reader/bin/boko")
  let settings = InMemorySettingsStore()
  let converter = FakeFormatConverter(isAvailable: false)
  let log = FakeActivityLog()

  func chooser(
    settings: InMemorySettingsStore? = nil, isExecutable: Bool = true
  ) -> ChooseConverterTool {
    ChooseConverterTool(
      settings: settings ?? self.settings, choice: converter, log: log,
      isExecutable: { _ in isExecutable })
  }

  @Test func savesAndUsesAToolThatCanRun() async throws {
    try await chooser()(tool)

    #expect(await settings.settings.bokoPath == "/Users/reader/bin/boko")
    #expect(converter.chosenTool == tool)
    #expect(log.summary == ["info APP boko is now /Users/reader/bin/boko"])
  }

  @Test func refusesAFileThatCannotRun() async {
    await #expect(throws: ConverterChoiceError.notExecutable) {
      try await chooser(isExecutable: false)(tool)
    }
    #expect(await settings.settings.bokoPath == nil)
    #expect(converter.chosenTool == nil)
    #expect(log.summary == ["warning APP /Users/reader/bin/boko isn't a program Sendle can run"])
  }

  @Test func resettingGoesBackToTheUsualFolders() async throws {
    try await chooser()(tool)

    try await chooser()(nil)

    #expect(await settings.settings.bokoPath == nil)
    #expect(converter.chosenTool == nil)
    #expect(log.summary.last == "info APP Looking for boko in the usual folders again")
  }

  @Test func aFailedSaveKeepsThePreviousChoice() async {
    let failing = InMemorySettingsStore(failure: .writeFailed("disk full"))

    await #expect(throws: ConverterChoiceError.storage(.writeFailed("disk full"))) {
      try await chooser(settings: failing)(tool)
    }
    #expect(converter.chosenTool == nil)
  }

  @Test func handsTheSavedChoiceToTheConverterAtLaunch() async {
    let saved = InMemorySettingsStore(AppSettings(bokoPath: "/Users/reader/bin/boko"))

    await chooser(settings: saved).restore()

    #expect(converter.chosenTool == tool)
  }

  @Test func onlyAnExecutableFileCanRun() throws {
    let folder = try makeTemporaryDirectory()
    let script = folder.appending(path: "boko")
    try Data("#!/bin/sh\n".utf8).write(to: script)

    #expect(!ChooseConverterTool.isExecutableFile(script))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    #expect(ChooseConverterTool.isExecutableFile(script))
    #expect(!ChooseConverterTool.isExecutableFile(folder))
  }
}
