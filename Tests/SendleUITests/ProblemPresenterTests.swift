import Foundation
import SendleDomain
import SendleUI
import Testing

struct ProblemPresenterTests {
  @Test(
    arguments: [
      (
        LibraryError.accessDenied, "Sendle can't see your Books library",
        FixAction.openPrivacySettings
      ),
      (.notFound, "Sendle can't find a Books library", .retry),
      (
        .unsupportedSchema(missingColumns: ["ZPATH"]), "This version of Books isn't supported yet",
        nil
      ),
      (.unreadable("I/O error"), "Sendle couldn't read your Books library", .retry),
    ] as [(LibraryError, String, FixAction?)])
  func explainsLibraryErrors(error: LibraryError, title: String, fix: FixAction?) {
    let problem = ProblemPresenter.problem(for: error)

    #expect(problem.title == title)
    #expect(problem.fix?.action == fix)
  }

  @Test func namesTheColumnsAnOlderBooksLacks() {
    let problem = ProblemPresenter.problem(
      for: .unsupportedSchema(missingColumns: ["ZPATH", "ZTITLE"]))

    #expect(problem.message?.contains("ZPATH, ZTITLE") == true)
  }

  @Test(
    arguments: [
      (
        SendFailure.authenticationFailed(.gmail), "Gmail didn't accept the password",
        FixAction.openSettings(.sender)
      ),
      (
        .authenticationFailed(.custom), "The mail server didn't accept the password",
        .openSettings(.sender)
      ),
      (.connectionFailed(host: "smtp.gmail.com"), "Couldn't reach smtp.gmail.com", .retry),
      (.rejected("552 too big"), "The mail server refused the message", nil),
      (.notConfigured, "Set up your Kindle email first", .openSettings(.kindle)),
      (.protected, "Protected by Apple (DRM), can't be sent", nil),
      (.inCloudOnly, "In iCloud only. Open it in Books to download.", nil),
      (.missing, "The file is no longer on this Mac", nil),
      (.invalidBook("no OPF"), "This EPUB is damaged and can't be prepared", nil),
      (.conversionUnavailable, "Your Kindle can't read EPUB over USB", .useDestination(.email)),
      (.conversionFailed("error"), "Calibre couldn't convert this book", .useDestination(.email)),
      (.deviceDisconnected, "The Kindle was unplugged during the copy", .retry),
      (.diskFull, "Not enough space on the Kindle", nil),
      (.localStorage("disk full"), "Couldn't write temporary files on this Mac", nil),
      (.cancelled, "Cancelled", nil),
      (.unconfirmed(host: "smtp.gmail.com"), "smtp.gmail.com didn't confirm the book", nil),
      (
        .passwordUnavailable, "Sendle couldn't read the app password",
        .openSettings(.sender)
      ),
    ] as [(SendFailure, String, FixAction?)])
  func explainsSendFailures(failure: SendFailure, title: String, fix: FixAction?) {
    let problem = ProblemPresenter.problem(for: failure)

    #expect(problem.title == title)
    #expect(problem.fix?.action == fix)
  }

  @Test(
    arguments: [
      (ProblemPresenter.problem(for: LibraryError.notFound), "Retry"),
      (ProblemPresenter.problem(for: LibraryError.unreadable("x")), "Retry"),
      (ProblemPresenter.problem(for: LibraryError.accessDenied), "Open Privacy Settings"),
      (ProblemPresenter.problem(for: SendFailure.connectionFailed(host: "h")), "Retry"),
      (ProblemPresenter.problem(for: SendFailure.conversionUnavailable), "Send by email"),
      (ProblemPresenter.problem(for: SendFailure.conversionFailed("e")), "Send by email"),
      (ProblemPresenter.problem(for: SendFailure.notConfigured), "Open Settings"),
    ] as [(Problem, String)])
  func labelsEachFixInSentenceCase(problem: Problem, label: String) {
    #expect(problem.fix?.label == label)
  }

  @Test func givesEachProviderItsOwnPasswordHint() {
    let hints = MailProvider.allCases.map {
      ProblemPresenter.problem(for: .authenticationFailed($0)).message
    }

    #expect(hints[0]?.contains("2-Step Verification") == true)
    #expect(Set(hints).count == MailProvider.allCases.count)
  }

  @Test func warnsAgainstSendingAnUnconfirmedBookTwice() {
    let problem = ProblemPresenter.problem(for: .unconfirmed(host: "smtp.mail.me.com"))

    #expect(problem.message == "It may still arrive. Check your Kindle before you send it again.")
  }

  @Test func namesEachProviderMidSentence() {
    #expect(
      MailProvider.allCases.map(\.inlineName) == [
        "Gmail", "iCloud Mail", "Fastmail", "the mail server",
      ])
  }

  @Test func blamesAmazonOnlyForAmazonsOwnLimit() {
    let amazon = ProblemPresenter.problem(
      for: .tooLarge(bytes: 62_000_000, limit: FormatPolicy.emailSizeLimit))
    let server = ProblemPresenter.problem(for: .tooLarge(bytes: 30_000_000, limit: 25_000_000))

    #expect(amazon.title == "62 MB is over Amazon's 50 MB email limit")
    #expect(server.title == "30 MB is over your mail server's 25 MB limit")
  }

  @Test func offersUSBForALargeBookOnlyWhileAKindleIsPluggedIn() {
    let failure = SendFailure.tooLarge(bytes: 62_000_000, limit: FormatPolicy.emailSizeLimit)

    #expect(ProblemPresenter.problem(for: failure).fix == nil)
    #expect(
      ProblemPresenter.problem(for: failure, kindleConnected: true).fix?.action
        == .useDestination(.usb))
  }

  @Test func saysWhereUnreadableSettingsWent() {
    let file = URL(filePath: "/Users/me/Library/Application Support/Sendle/settings.corrupt-1.json")

    let problem = ProblemPresenter.settingsSetAside(file)

    #expect(problem.title == "Sendle couldn't read its settings")
    #expect(problem.message?.contains("settings.corrupt-1.json") == true)
    #expect(problem.fix?.action == .openSettings(.kindle))
  }
}
