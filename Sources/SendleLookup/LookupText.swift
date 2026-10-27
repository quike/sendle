import Foundation
import SendleDomain

/// The first run of exactly four ASCII digits, such as the year in "October 1, 1988".
package func firstYear(in text: String) -> String? {
  text.split { !($0.isASCII && $0.isWholeNumber) }.first { $0.count == 4 }.map(String.init)
}

/// The ISBN-13 an edition is found under: `searched` when the record lists it, else the first
/// valid one the record lists.
package func foundISBN(in listed: [String], searched: String?) -> String? {
  let isbns = listed.compactMap(ISBN.normalised)
  return searched.flatMap { isbns.contains($0) ? $0 : nil } ?? isbns.first
}

private let queryValueAllowed = CharacterSet.urlQueryAllowed
  .subtracting(CharacterSet(charactersIn: "+&=/?"))

/// `text` as a query value, with "+ & = / ?" percent-encoded too, so none reads as syntax.
package func queryEscaped(_ text: String) -> String {
  text.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? text
}
