import Foundation

enum LanguageTag {
  /// The lowercased primary subtag of "pt_BR", "pt-BR" or "PT", or nil when there is none.
  static func primary(_ tag: String) -> String? {
    let text = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let primary = text.prefix { $0 != "-" && $0 != "_" }
    return primary.isEmpty ? nil : String(primary)
  }
}
