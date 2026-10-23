import Foundation

public enum ConverterChoiceError: Error, Hashable, Sendable {
  case notExecutable
  case storage(StorageError)
}

/// Points Sendle at a boko the user picked, or back at the usual folders.
public struct ChooseConverterTool: Sendable {
  public typealias Check = @Sendable (URL) -> Bool

  private let settings: any SettingsStore
  private let choice: any ToolChoice
  private let log: any ActivityLog
  private let isExecutable: Check

  public init(
    settings: any SettingsStore,
    choice: any ToolChoice,
    log: any ActivityLog = NoActivityLog(),
    isExecutable: @escaping Check = ChooseConverterTool.isExecutableFile
  ) {
    self.settings = settings
    self.choice = choice
    self.log = log
    self.isExecutable = isExecutable
  }

  /// Saves `tool` and uses it from now on; nil goes back to the usual folders.
  public func callAsFunction(_ tool: URL?) async throws(ConverterChoiceError) {
    if let tool, !isExecutable(tool) {
      log.warning(.app, "\(tool.path) isn't a program Sendle can run")
      throw .notExecutable
    }
    do throws(StorageError) {
      try await settings.update { $0.bokoPath = tool?.path }
    } catch {
      log.error(.app, "Couldn't save boko's location: \(error.detail)")
      throw .storage(error)
    }
    choice.choose(tool)
    log.info(
      .app, tool.map { "boko is now \($0.path)" } ?? "Looking for boko in the usual folders again")
  }

  /// Hands the saved choice to the converter when Sendle starts.
  public func restore() async {
    choice.choose(await settings.load().bokoPath.map { URL(filePath: $0) })
  }

  /// A regular file, not a folder, that this user may run.
  public static func isExecutableFile(_ url: URL) -> Bool {
    var isFolder: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
      && !isFolder.boolValue && FileManager.default.isExecutableFile(atPath: url.path)
  }
}
