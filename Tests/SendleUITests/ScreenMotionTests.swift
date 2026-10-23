import SendleUI
import SwiftUI
import Testing

struct ScreenMotionTests {
  @Test func settingsTheLogsAndTheDuplicatesComeUpOverTheCard() {
    #expect(ScreenMotion.sheet(reduceMotion: false) == .cover)
  }

  /// The front page waits on the leading side and a section on the trailing one, so opening a
  /// section pushes it in from the right and going back pops it out the way it came.
  @Test func settingsPagesPushAndPop() {
    #expect(ScreenMotion.settingsPage(nil, reduceMotion: false) == .slide(.leading))
    for section in SettingsSection.allCases {
      #expect(ScreenMotion.settingsPage(section, reduceMotion: false) == .slide(.trailing))
    }
  }

  @Test func theBooksSlideFromTheirSideOfTheSwitch() {
    #expect(ScreenMotion.books(.library, reduceMotion: false) == .slide(.leading))
    #expect(ScreenMotion.books(.kindle, reduceMotion: false) == .slide(.trailing))
  }

  @Test func reduceMotionFadesInsteadOfMoving() {
    #expect(ScreenMotion.sheet(reduceMotion: true) == .fade)
    #expect(ScreenMotion.settingsPage(nil, reduceMotion: true) == .fade)
    #expect(ScreenMotion.settingsPage(.general, reduceMotion: true) == .fade)
    #expect(ScreenMotion.books(.library, reduceMotion: true) == .fade)
    #expect(ScreenMotion.books(.kindle, reduceMotion: true) == .fade)
  }
}
