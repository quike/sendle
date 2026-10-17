import Foundation
import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct CalibreConverterTests {
  let applications: URL
  let staging: URL
  let epub: PreparedFile

  init() throws {
    applications = try makeTemporaryDirectory()
    staging = try makeTemporaryDirectory()
    let url = staging.appending(path: "Moby-Dick - Herman Melville.epub")
    try Data("epub".utf8).write(to: url)
    epub = PreparedFile(url: url, format: .epub, fixes: [.addedLanguage])
  }

  /// Installs a fake `ebook-convert` that runs `script`, in a folder like /Applications.
  @discardableResult
  func installCalibre(_ script: String, in folder: URL? = nil) throws -> URL {
    let tool = (folder ?? applications).appending(path: "calibre.app/Contents/MacOS/ebook-convert")
    try FileManager.default.createDirectory(
      at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n\(script)\n".utf8).write(to: tool)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    return tool
  }

  func converter(timeout: Duration = .seconds(30)) -> CalibreConverter {
    CalibreConverter(folders: [applications], timeout: timeout)
  }

  func convert(_ converter: CalibreConverter) async -> Result<PreparedFile, SendFailure> {
    do throws(SendFailure) {
      return .success(try await converter.convert(epub, to: .azw3, in: staging))
    } catch {
      return .failure(error)
    }
  }

  // MARK: Finding Calibre

  @Test func findsCalibreInTheFirstFolderThatHasIt() throws {
    let empty = try makeTemporaryDirectory()
    let tool = try installCalibre("exit 0")

    let converter = CalibreConverter(folders: [empty, applications], timeout: .seconds(1))

    #expect(converter.toolURL == tool)
    #expect(converter.isAvailable)
  }

  @Test func isUnavailableWithoutCalibre() async {
    #expect(converter().toolURL == nil)
    #expect(await convert(converter()) == .failure(.conversionUnavailable))
  }

  @Test func ignoresACalibreThatCannotRun() throws {
    let tool = try installCalibre("exit 0")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tool.path)

    #expect(converter().toolURL == nil)
  }

  @Test func noticesCalibreInstalledAfterLaunch() throws {
    let converter = converter()
    #expect(!converter.isAvailable)

    try installCalibre("exit 0")

    #expect(converter.isAvailable)
  }

  // MARK: Converting

  @Test func convertsForAKindleNextToTheEPUB() async throws {
    try installCalibre(#"printf '%s\n' "$@" > "$(dirname "$2")/arguments.txt"; cp "$1" "$2""#)

    let result = await convert(converter())

    let output = staging.appending(path: "Moby-Dick - Herman Melville.azw3")
    #expect(result == .success(PreparedFile(url: output, format: .azw3)))
    let arguments = try String(
      contentsOf: staging.appending(path: "arguments.txt"), encoding: .utf8)
    #expect(arguments == "\(epub.url.path)\n\(output.path)\n--output-profile\nkindle\n")
  }

  @Test func passesOnWhatCalibreSaidWhenItFails() async throws {
    try installCalibre(
      """
      echo "Converting input to HTML..."
      echo "Traceback (most recent call last):" >&2
      echo "ValueError: No OPF file found in the EPUB" >&2
      exit 1
      """)

    let result = await convert(converter())

    #expect(
      result
        == .failure(
          .conversionFailed(
            "Converting input to HTML...\nTraceback (most recent call last):\n"
              + "ValueError: No OPF file found in the EPUB")))
  }

  @Test func failsWhenCalibreWritesNothing() async throws {
    try installCalibre("exit 0")

    #expect(await convert(converter()) == .failure(.conversionFailed("Calibre made no book.")))
  }

  @Test func stopsCalibreAfterTheTimeout() async throws {
    try installCalibre("exec sleep 30")

    let result = await convert(converter(timeout: .milliseconds(300)))

    guard case .failure(.conversionFailed(let message)) = result else {
      Issue.record("Expected a conversion failure, got \(result)")
      return
    }
    #expect(message.hasPrefix("Calibre was still converting after"))
  }

  @Test func cancellingStopsCalibre() async throws {
    try installCalibre(#"touch "$(dirname "$2")/started"; exec sleep 30"#)
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

  @Test func reportsACalibreThatWontStart() async throws {
    try installCalibre("exit 0")
    let tool = applications.appending(path: "calibre.app/Contents/MacOS/ebook-convert")
    try Data("not a script".utf8).write(to: tool)

    let result = await convert(converter())

    guard case .failure(.conversionFailed(let message)) = result else {
      Issue.record("Expected a conversion failure, got \(result)")
      return
    }
    #expect(message.hasPrefix("Couldn't start Calibre"))
  }
}
