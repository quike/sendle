import CoreGraphics
import Foundation
import SendleDomain
import SendleTestSupport

/// A temporary Kindle: a root with `documents` and `system`, and a folder for listing caches.
struct KindleTree {
  let root: URL
  let cache: URL

  init() throws {
    root = try makeVolumeRoot()
    cache = try makeTemporaryDirectory()
  }

  var documents: URL { root.appending(path: "documents", directoryHint: .isDirectory) }

  var volume: KindleVolume { KindleVolume(id: "kindle", name: "Kindle", mountURL: root) }

  func cacheFile(_ device: String) -> URL {
    cache.appending(path: "kindles").appending(path: "\(device).json")
  }

  func write(_ path: String, _ contents: Data) throws {
    try put(documents.appending(path: path), contents)
  }

  func write(_ path: String, _ contents: String) throws {
    try write(path, Data(contents.utf8))
  }

  func writeRoot(_ path: String, _ contents: Data) throws {
    try put(root.appending(path: path), contents)
  }

  func writeRoot(_ path: String, _ contents: String) throws {
    try writeRoot(path, Data(contents.utf8))
  }

  private func put(_ url: URL, _ contents: Data) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url)
  }
}

/// A one-page PDF with the given document title and author.
func makePDF(title: String?, author: String?) -> Data {
  var info: [CFString: Any] = [:]
  if let title { info[kCGPDFContextTitle] = title }
  if let author { info[kCGPDFContextAuthor] = author }
  let data = NSMutableData()
  var box = CGRect(x: 0, y: 0, width: 200, height: 300)
  guard let consumer = CGDataConsumer(data: data),
    let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)
  else { return Data() }
  context.beginPDFPage(nil)
  context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
  context.fill(box)
  context.endPDFPage()
  context.closePDF()
  return data as Data
}
