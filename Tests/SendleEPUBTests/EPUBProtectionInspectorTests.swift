import Foundation
import SendleDomain
import SendleEPUB
import SendleTestSupport
import Testing

struct EPUBProtectionInspectorTests {
  let folder: URL
  let root: URL
  let inspector = EPUBProtectionInspector()

  init() throws {
    folder = try makeTemporaryDirectory()
    root = folder.appending(path: "Moby-Dick.epub", directoryHint: .isDirectory)
  }

  @Test func passesABookWithoutDRM() throws {
    try EPUBFixture.book().write(to: root)

    #expect(!inspector.isProtected(book()))
  }

  @Test(arguments: ["META-INF/sinf.xml", "META-INF/rights.xml"])
  func flagsFairPlayAndAdobeRights(file: String) throws {
    var epub = EPUBFixture.book()
    epub[text: file] = "<rights/>"
    try epub.write(to: root)

    #expect(inspector.isProtected(book()))
  }

  @Test func passesObfuscatedFontsOnly() throws {
    try write(
      encryption: """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
          <enc:EncryptedData>
            <enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
            <enc:CipherData><enc:CipherReference URI="OEBPS/fonts/serif"/></enc:CipherData>
          </enc:EncryptedData>
          <enc:EncryptedData>
            <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
            <enc:CipherData><enc:CipherReference URI="OEBPS/fonts/Sans%20Bold.OTF"/></enc:CipherData>
          </enc:EncryptedData>
        </encryption>
        """)

    #expect(!inspector.isProtected(book()))
  }

  @Test func flagsEncryptedContent() throws {
    try write(
      encryption: """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
          <enc:EncryptedData>
            <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
            <enc:KeyInfo><enc:EncryptedKey><enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/></enc:EncryptedKey></enc:KeyInfo>
            <enc:CipherData><enc:CipherReference URI="OEBPS/chapter1.xhtml"/></enc:CipherData>
          </enc:EncryptedData>
        </encryption>
        """)

    #expect(inspector.isProtected(book()))
  }

  @Test func treatsAnUnreadableEncryptionManifestAsProtected() throws {
    try write(encryption: "<encryption><unclosed>")

    #expect(inspector.isProtected(book()))
  }

  @Test func passesAnEmptyEncryptionManifest() throws {
    try write(encryption: #"<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"/>"#)

    #expect(!inspector.isProtected(book()))
  }

  @Test func onlyInspectsEPUBFolders() throws {
    var epub = EPUBFixture.book()
    epub[text: "META-INF/sinf.xml"] = "<sinf/>"
    try epub.write(to: root)
    let file = folder.appending(path: "Zipped.epub")
    try Data("zip".utf8).write(to: file)

    #expect(!inspector.isProtected(book(format: .pdf)))
    #expect(!inspector.isProtected(book(at: file)))
    #expect(!inspector.isProtected(book(at: folder.appending(path: "Missing.epub"))))
  }

  private func write(encryption: String) throws {
    var epub = EPUBFixture.book()
    epub[text: "META-INF/encryption.xml"] = encryption
    try epub.write(to: root)
  }

  private func book(format: BookFormat = .epub, at url: URL? = nil) -> Book {
    .fixture(format: format, fileURL: url ?? root)
  }
}
