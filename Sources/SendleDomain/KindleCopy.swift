/// How a USB send names a book and seeds its ASIN.
public struct KindleCopy: Hashable, Sendable {
  /// 1 is the book's own name; from 2, "Title - Author (n)".
  public var name: Int
  /// Which copy's ASIN seed it gets, from 1.
  public var asin: Int
  /// Replace in place: the old copy's ASIN, kept as it is, so the Kindle keeps its reading
  /// position and cover.
  public var keptASIN: String?
  /// The Kindle's copy of this book that goes once the new one is delivered, when it isn't
  /// overwritten.
  public var removes: KindleBook?

  public init(name: Int, asin: Int, keptASIN: String? = nil, removes: KindleBook? = nil) {
    self.name = name
    self.asin = asin
    self.keptASIN = keptASIN
    self.removes = removes
  }

  /// Keep both: copy n, numbered from 2, under its own name and ASIN.
  public static func keepBoth(_ copy: Int) -> KindleCopy {
    KindleCopy(name: copy, asin: copy)
  }

  public static func replacing(asin: String) -> KindleCopy {
    KindleCopy(name: 1, asin: 1, keptASIN: asin)
  }
}
