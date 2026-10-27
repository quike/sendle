/// The first run of exactly four ASCII digits, such as the year in "October 1, 1988".
package func firstYear(in text: String) -> String? {
  text.split { !($0.isASCII && $0.isWholeNumber) }.first { $0.count == 4 }.map(String.init)
}
