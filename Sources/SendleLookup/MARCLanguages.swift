/// The MARC language codes Open Library uses, as BCP 47 tags.
package enum MARCLanguages {
  private static let tags: [String: String] = [
    "afr": "af", "ara": "ar", "baq": "eu", "bre": "br", "cat": "ca", "chi": "zh", "cor": "kw",
    "cos": "co", "cze": "cs", "dan": "da", "dut": "nl", "eng": "en", "fin": "fi", "fre": "fr",
    "frr": "frr", "fry": "fy", "ger": "de", "gla": "gd", "gle": "ga", "glg": "gl", "glv": "gv",
    "gre": "el", "gsw": "gsw", "guj": "gu", "heb": "he", "hin": "hi", "hun": "hu", "ice": "is",
    "ita": "it", "jpn": "ja", "kor": "ko", "lat": "la", "ltz": "lb", "mal": "ml", "mar": "mr",
    "nno": "nn", "nob": "nb", "nor": "nb", "oci": "oc", "pol": "pl", "por": "pt", "roh": "rm",
    "rum": "ro", "rus": "ru", "sco": "sco", "spa": "es", "swe": "sv", "tam": "ta", "tur": "tr",
    "ukr": "uk", "wel": "cy",
  ]

  package static func bcp47(_ code: String) -> String? {
    tags[code]
  }
}
