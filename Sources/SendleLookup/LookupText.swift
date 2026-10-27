import Foundation

/// The first run of exactly four ASCII digits, such as the year in "October 1, 1988".
package func firstYear(in text: String) -> String? {
  text.split { !($0.isASCII && $0.isWholeNumber) }.first { $0.count == 4 }.map(String.init)
}

private let queryValueAllowed = CharacterSet.urlQueryAllowed
  .subtracting(CharacterSet(charactersIn: "+&=/?"))

/// `text` as a query value, with "+ & = / ?" percent-encoded too, so none reads as syntax.
package func queryEscaped(_ text: String) -> String {
  text.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? text
}
