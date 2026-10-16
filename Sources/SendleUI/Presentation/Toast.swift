/// A message at the bottom of a screen: green for success, red for a failure.
package struct Toast: Hashable, Sendable {
  package enum Tone: Hashable, Sendable {
    case success
    case failure
  }

  package let tone: Tone
  package let title: String
  package let message: String?
  package let fix: Fix?

  package init(tone: Tone, title: String, message: String? = nil, fix: Fix? = nil) {
    self.tone = tone
    self.title = title
    self.message = message
    self.fix = fix
  }

  package init(tone: Tone, _ problem: Problem) {
    self.init(tone: tone, title: problem.title, message: problem.message, fix: problem.fix)
  }
}
