import SendleEPUB
import Testing

struct XMLDeclarationFixTests {
  @Test func addsADeclarationToADocumentWithout() {
    let before = #"<html xmlns="http://www.w3.org/1999/xhtml"><body/></html>"#

    #expect(
      XMLDeclarationFix.apply(to: before)
        == """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body/></html>
        """)
  }

  @Test func completesADeclarationWithoutAnEncoding() {
    let before = """
      <?xml version="1.0"?>
      <html/>
      """

    #expect(
      XMLDeclarationFix.apply(to: before)
        == """
        <?xml version="1.0" encoding="utf-8"?>
        <html/>
        """)
  }

  @Test(arguments: [
    #"<?xml version="1.0" encoding="utf-8"?><html/>"#,
    "<?xml version='1.0' encoding='UTF-8'?><html/>",
    #"<?xml version="1.0" encoding="iso-8859-1"?><html/>"#,
    "\n  <?xml version=\"1.0\" encoding=\"utf-8\"?><html/>",
  ])
  func leavesADeclaredEncodingAlone(document: String) {
    #expect(XMLDeclarationFix.apply(to: document) == nil)
  }
}

struct LanguageFixTests {
  let package = """
    <package xmlns="http://www.idpf.org/2007/opf">
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Moby-Dick</dc:title>
    </metadata>
    </package>
    """

  @Test func addsTheBooksLanguageBeforeTheEndOfTheMetadata() {
    #expect(
      LanguageFix.apply(to: package, hasLanguage: false, language: "es")
        == """
        <package xmlns="http://www.idpf.org/2007/opf">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>Moby-Dick</dc:title>
        <dc:language xmlns:dc="http://purl.org/dc/elements/1.1/">es</dc:language>
        </metadata>
        </package>
        """)
  }

  @Test func handlesAPrefixedMetadataElement() {
    let prefixed = "<opf:package><opf:metadata></opf:metadata></opf:package>"

    #expect(
      LanguageFix.apply(to: prefixed, hasLanguage: false, language: nil)
        == "<opf:package><opf:metadata>"
        + #"<dc:language xmlns:dc="http://purl.org/dc/elements/1.1/">en</dc:language>"#
        + "\n</opf:metadata></opf:package>")
  }

  @Test(
    arguments: [
      ("pt_BR", "pt-BR"), ("en-GB", "en-GB"), ("fra", "fra"), (nil, "en"), ("", "en"),
      ("<script>", "en"), ("English", "en"),
    ] as [(String?, String)])
  func usesAValidLanguageTagOrEnglish(language: String?, expected: String) {
    let fixed = LanguageFix.apply(to: package, hasLanguage: false, language: language)

    #expect(fixed?.contains(">\(expected)</dc:language>") == true)
  }

  @Test func leavesAPackageWithALanguageOrWithoutMetadataAlone() {
    #expect(LanguageFix.apply(to: package, hasLanguage: true, language: "es") == nil)
    #expect(LanguageFix.apply(to: "<package/>", hasLanguage: false, language: "es") == nil)
  }
}
