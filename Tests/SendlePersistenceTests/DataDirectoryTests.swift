import SendlePersistence
import Testing

struct DataDirectoryTests {
  @Test func defaultsToApplicationSupport() {
    let url = DataDirectory.url(environment: [:])
    #expect(url.path(percentEncoded: false).hasSuffix("Library/Application Support/Sendle/"))
  }

  @Test func honoursTheEnvironmentOverride() {
    let url = DataDirectory.url(environment: ["SENDLE_DATA_DIR": "/tmp/sendle-dev"])
    #expect(url.path() == "/tmp/sendle-dev/")
  }
}
