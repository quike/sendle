enum ThumbnailName {
  static let folder = "system/thumbnails"

  /// "thumbnail_<asin>_<type>_portrait.jpg"
  static func of(asin: String, type: String) -> String {
    "thumbnail_\(asin)_\(type)_portrait.jpg"
  }
}
