/// How a USB send delivers a book the Kindle already has a copy of.
public enum KindleCopy: Hashable, Sendable {
  /// Keep both: copy n, numbered from 2, under its own name and ASIN.
  case keepBoth(Int)
  /// Replace in place: the new copy keeps the old copy's ASIN, so the Kindle keeps its reading
  /// position and cover.
  case replacing(asin: String)
}
