import Foundation
import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct BokoConverterTests {
  let bin: URL
  let staging: URL
  let epub: PreparedFile

  init() throws {
    bin = try makeTemporaryDirectory()
    staging = try makeTemporaryDirectory()
    let url = staging.appending(path: "Moby-Dick - Herman Melville.epub")
    try Data("epub".utf8).write(to: url)
    epub = PreparedFile(url: url, format: .epub, fixes: [.addedLanguage])
  }

  /// Installs a fake `boko` that runs `script`, in a folder like ~/.cargo/bin.
  @discardableResult
  func installBoko(_ script: String, in folder: URL? = nil) throws -> URL {
    let tool = (folder ?? bin).appending(path: "boko")
    try Data("#!/bin/sh\n\(script)\n".utf8).write(to: tool)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    return tool
  }

  let log = FakeActivityLog()

  func converter(timeout: Duration = .seconds(30)) -> BokoConverter {
    BokoConverter(folders: [bin], timeout: timeout, log: log)
  }

  func convert(_ converter: BokoConverter) async -> Result<PreparedFile, SendFailure> {
    do throws(SendFailure) {
      return .success(try await converter.convert(epub, to: .azw3, in: staging))
    } catch {
      return .failure(error)
    }
  }

  // MARK: Finding boko

  @Test func findsBokoInTheFirstFolderThatHasIt() throws {
    let empty = try makeTemporaryDirectory()
    let tool = try installBoko("exit 0")

    let converter = BokoConverter(folders: [empty, bin], timeout: .seconds(1))

    #expect(converter.toolURL == tool)
    #expect(converter.isAvailable)
  }

  @Test func looksFirstWhereCargoAndBokosInstallerPutIt() {
    let cargo = FileManager.default.homeDirectoryForCurrentUser.appending(
      path: ".cargo/bin", directoryHint: .isDirectory)

    #expect(BokoConverter.folders.first == cargo)
  }

  @Test func aChosenBokoIsUsedInsteadOfTheUsualFolders() throws {
    try installBoko("exit 0")
    let chosen = try installBoko("exit 0", in: try makeTemporaryDirectory())
    let converter = converter()

    converter.choose(chosen)

    #expect(converter.chosenTool == chosen)
    #expect(converter.toolURL == chosen)
  }

  @Test func aChosenBokoThatIsGoneIsNotFoundEvenWhenTheUsualFoldersHaveOne() throws {
    try installBoko("exit 0")
    let converter = converter()

    converter.choose(URL(filePath: "/Users/reader/gone/boko"))

    #expect(converter.toolURL == nil)
  }

  @Test func resettingTheChoiceLooksInTheUsualFoldersAgain() throws {
    let tool = try installBoko("exit 0")
    let converter = converter()
    converter.choose(URL(filePath: "/Users/reader/gone/boko"))

    converter.choose(nil)

    #expect(converter.chosenTool == nil)
    #expect(converter.toolURL == tool)
  }

  @Test func isUnavailableWithoutBoko() async {
    #expect(converter().toolURL == nil)
    #expect(await convert(converter()) == .failure(.conversionUnavailable))
  }

  @Test func ignoresABokoThatCannotRun() throws {
    let tool = try installBoko("exit 0")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tool.path)

    #expect(converter().toolURL == nil)
  }

  @Test func noticesBokoInstalledAfterLaunch() throws {
    let converter = converter()
    #expect(!converter.isAvailable)

    try installBoko("exit 0")

    #expect(converter.isAvailable)
  }

  // MARK: Converting

  @Test func convertsNextToTheEPUB() async throws {
    try installBoko(#"printf '%s\n' "$@" > "$(dirname "$3")/arguments.txt"; cp "$2" "$3""#)

    let result = await convert(converter())

    let output = staging.appending(path: "Moby-Dick - Herman Melville.azw3")
    #expect(result == .success(PreparedFile(url: output, format: .azw3)))
    let arguments = try String(
      contentsOf: staging.appending(path: "arguments.txt"), encoding: .utf8)
    #expect(arguments == "convert\n\(epub.url.path)\n\(output.path)\n")
  }

  // MARK: Logs

  @Test func logsTheCommandAndWhatBokoPrinted() async throws {
    let tool = try installBoko(
      """
      echo "Reading Moby-Dick - Herman Melville.epub"
      echo "Writing AZW3"
      cp "$2" "$3"
      """)

    _ = await convert(converter())

    let lines = log.summary
    #expect(
      lines.first
        == "info BOKO Running \(tool.path) convert \"Moby-Dick - Herman Melville.epub\" "
        + "\"Moby-Dick - Herman Melville.azw3\"")
    #expect(lines.contains("debug BOKO Reading Moby-Dick - Herman Melville.epub\nWriting AZW3"))
    #expect(lines.contains { $0.hasPrefix("info BOKO boko finished in ") })
  }

  @Test func logsHowBokoStopped() async throws {
    try installBoko("echo oops; exit 3")

    _ = await convert(converter())

    #expect(log.summary.contains("debug BOKO oops"))
    #expect(log.summary.last?.hasPrefix("error BOKO boko stopped with status 3 after ") == true)
  }

  @Test func logsATimeout() async throws {
    try installBoko("exec sleep 30")

    _ = await convert(converter(timeout: .milliseconds(300)))

    #expect(log.summary.last?.hasPrefix("error BOKO boko was still converting after") == true)
  }

  @Test func leavesABookItCannotReadAsBokoWroteIt() async throws {
    try installBoko(#"cp "$2" "$3""#)

    let result = await convert(converter())

    let output = staging.appending(path: "Moby-Dick - Herman Melville.azw3")
    #expect(result == .success(PreparedFile(url: output, format: .azw3)))
    #expect(try Data(contentsOf: output) == Data("epub".utf8))
  }

  @Test func passesOnWhatBokoSaidWhenItFails() async throws {
    try installBoko(
      """
      echo "Reading Moby-Dick - Herman Melville.epub"
      echo "Error: failed to parse the package document" >&2
      echo "Caused by: missing <manifest>" >&2
      echo "Location: src/epub.rs:42" >&2
      exit 1
      """)

    let result = await convert(converter())

    #expect(
      result
        == .failure(
          .conversionFailed(
            "Error: failed to parse the package document\nCaused by: missing <manifest>\n"
              + "Location: src/epub.rs:42")))
  }

  @Test func saysHowBokoStoppedWhenItSaidNothing() async throws {
    try installBoko("exit 3")

    #expect(
      await convert(converter()) == .failure(.conversionFailed("boko stopped with status 3.")))
  }

  @Test func failsWhenBokoWritesNothing() async throws {
    try installBoko("exit 0")

    #expect(await convert(converter()) == .failure(.conversionFailed("boko made no book.")))
  }

  @Test func stopsBokoAfterTheTimeout() async throws {
    try installBoko("exec sleep 30")

    let result = await convert(converter(timeout: .milliseconds(300)))

    guard case .failure(.conversionFailed(let message)) = result else {
      Issue.record("Expected a conversion failure, got \(result)")
      return
    }
    #expect(message.hasPrefix("boko was still converting after"))
  }

  @Test func wordsTheTimeoutInEnglishInEveryLanguage() {
    #expect(
      BokoConverter.timeoutMessage(after: .seconds(300))
        == "boko was still converting after 5 minutes, so Sendle stopped it.")
  }

  @Test func cancellingStopsBoko() async throws {
    try installBoko(#"touch "$(dirname "$3")/started"; exec sleep 30"#)
    let converter = converter()
    let started = staging.appending(path: "started")
    let conversion = Task { await convert(converter) }
    #expect(await eventually { FileManager.default.fileExists(atPath: started.path) })
    let clock = ContinuousClock()
    let start = clock.now

    conversion.cancel()

    #expect(await conversion.value == .failure(.cancelled))
    #expect(clock.now - start < .seconds(5))
  }

  @Test func reportsABokoThatWontStart() async throws {
    let tool = try installBoko("exit 0")
    try Data("not a script".utf8).write(to: tool)

    let result = await convert(converter())

    guard case .failure(.conversionFailed(let message)) = result else {
      Issue.record("Expected a conversion failure, got \(result)")
      return
    }
    #expect(message.hasPrefix("Couldn't start boko"))
  }
}
