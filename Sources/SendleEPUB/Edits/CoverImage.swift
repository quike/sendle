import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CoverImage {
  /// `image/jpg` isn't registered, but books declare JPEGs with it.
  private static let types: [String: UTType] = [
    "image/jpeg": .jpeg, "image/jpg": .jpeg, "image/png": .png,
  ]

  /// `image` encoded as `mediaType`, or as it is when it already has that type. Nil when the type
  /// isn't JPEG or PNG, or the image doesn't decode.
  static func data(from image: Data, mediaType: String) -> Data? {
    guard let type = types[mediaType.lowercased()],
      let source = CGImageSourceCreateWithData(image as CFData, nil),
      let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    if CGImageSourceGetType(source) as String? == type.identifier { return image }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output as CFMutableData, type.identifier as CFString, 1, nil)
    else { return nil }
    let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
    CGImageDestinationAddImage(destination, decoded, options)
    return CGImageDestinationFinalize(destination) ? output as Data : nil
  }
}
