import Foundation

public enum DataDirectory {
  public static let environmentKey = "SENDLE_DATA_DIR"

  /// `~/Library/Application Support/Sendle`, unless `SENDLE_DATA_DIR` points elsewhere.
  public static func url(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL {
    if let override = environment[environmentKey], !override.isEmpty {
      return URL(filePath: override, directoryHint: .isDirectory)
    }
    return URL.applicationSupportDirectory.appending(path: "Sendle", directoryHint: .isDirectory)
  }
}
