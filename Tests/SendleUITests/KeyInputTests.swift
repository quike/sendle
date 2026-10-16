import SendleUI
import Testing

struct KeyInputTests {
  @Test(
    arguments: [
      (KeyInput(.escape), PanelCommand.escape),
      (KeyInput(.escape, isEditingText: true), .escape),
      (KeyInput(.down), .move(.down)),
      (KeyInput(.left), .move(.left)),
      (KeyInput(.character("a"), command: true), .selectAll),
      (KeyInput(.character("1"), command: true), .layout(.grid)),
      (KeyInput(.character("2"), command: true), .layout(.list)),
      (KeyInput(.character("3"), command: true, isEditingText: true), .layout(.shelf)),
      (KeyInput(.character("f"), command: true), .focusSearch),
      (KeyInput(.character(","), command: true, isEditingText: true), .openSettings),
    ] as [(KeyInput, PanelCommand)])
  func mapsShortcutsToCommands(input: KeyInput, command: PanelCommand) {
    #expect(input.panelCommand == command)
  }

  @Test(arguments: [
    KeyInput(.down, isEditingText: true),
    KeyInput(.character("a"), command: true, isEditingText: true),
    KeyInput(.character("a")),
    KeyInput(.character("q"), command: true),
    KeyInput(.up, command: true),
  ])
  func leavesTypingToTheTextField(input: KeyInput) {
    #expect(input.panelCommand == nil)
  }
}
