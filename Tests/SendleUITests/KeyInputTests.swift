import AppKit
import SendleUI
import Testing

struct KeyInputTests {
  @Test(
    arguments: [
      (KeyInput(.escape), PanelCommand.escape),
      (KeyInput(.escape, isEditingText: true), .escape),
      (KeyInput(.down), .move(.down)),
      (KeyInput(.down, isEditingText: true), .move(.down)),
      (KeyInput(.left), .move(.left)),
      (KeyInput(.character("a"), command: true), .selectAll),
      (KeyInput(.character("1"), command: true), .layout(.grid)),
      (KeyInput(.character("2"), command: true), .layout(.list)),
      (KeyInput(.character("3"), command: true, isEditingText: true), .layout(.shelf)),
      (KeyInput(.character("f"), command: true), .focusSearch),
      (KeyInput(.character("r"), command: true), .refresh),
      (KeyInput(.character("R"), command: true, isEditingText: true), .refresh),
      (KeyInput(.character(","), command: true, isEditingText: true), .openSettings),
      (KeyInput(.returnKey), .confirm),
      (KeyInput(.returnKey, isEditingText: true), .confirm),
    ] as [(KeyInput, PanelCommand)])
  func mapsShortcutsToCommands(input: KeyInput, command: PanelCommand) {
    #expect(input.panelCommand == command)
  }

  @Test(arguments: [
    KeyInput(.left, isEditingText: true),
    KeyInput(.character("a"), command: true, isEditingText: true),
    KeyInput(.character("a")),
    KeyInput(.character("q"), command: true),
    KeyInput(.up, command: true),
    KeyInput(.returnKey, command: true),
  ])
  func leavesTypingToTheTextField(input: KeyInput) {
    #expect(input.panelCommand == nil)
  }

  @Test(
    arguments: [
      (UInt16(53), "\u{1b}", NSEvent.ModifierFlags(), KeyInput(.escape)),
      (36, "\r", [], KeyInput(.returnKey)),
      (76, "\u{3}", [], KeyInput(.returnKey)),
      (125, "", [.function, .numericPad], KeyInput(.down)),
      (0, "a", [.command, .capsLock], KeyInput(.character("a"), command: true)),
      (0, "a", [.command, .shift], KeyInput(.character("a"))),
      (3, "f", [.command], KeyInput(.character("f"), command: true)),
    ] as [(UInt16, String, NSEvent.ModifierFlags, KeyInput)])
  func readsAppKitKeys(
    keyCode: UInt16, characters: String, flags: NSEvent.ModifierFlags, input: KeyInput
  ) {
    #expect(
      KeyInput(keyCode: keyCode, characters: characters, modifierFlags: flags, isEditingText: false)
        == input)
  }

  @Test func remembersThatATextFieldIsBeingEdited() {
    let input = KeyInput(keyCode: 0, characters: "a", modifierFlags: [], isEditingText: true)

    #expect(input == KeyInput(.character("a"), isEditingText: true))
  }

  @Test func remembersThatAKeyIsHeldDown() {
    let input = KeyInput(
      keyCode: 36, characters: "\r", modifierFlags: [], isEditingText: false, isRepeat: true)

    #expect(input == KeyInput(.returnKey, isRepeat: true))
  }

  @Test func ignoresAKeyWithoutCharacters() {
    #expect(KeyInput(keyCode: 63, characters: nil, modifierFlags: [], isEditingText: false) == nil)
  }

  @Test(
    arguments: [
      ("x", NSEvent.ModifierFlags.command, TextEditingCommand.cut),
      ("c", [.command, .capsLock], .copy), ("v", [.command], .paste),
      ("a", [.command], .selectAll), ("z", [.command], .undo), ("Z", [.command, .shift], .redo),
    ] as [(String, NSEvent.ModifierFlags, TextEditingCommand)])
  func givesTextFieldsTheirEditingShortcuts(
    characters: String, flags: NSEvent.ModifierFlags, command: TextEditingCommand
  ) {
    #expect(TextEditingCommand(characters: characters, modifierFlags: flags) == command)
  }

  @Test(
    arguments: [
      ("v", NSEvent.ModifierFlags()), ("x", [.command, .shift]), ("q", [.command]),
    ] as [(String, NSEvent.ModifierFlags)])
  func leavesOtherKeysToThePanel(characters: String, flags: NSEvent.ModifierFlags) {
    #expect(TextEditingCommand(characters: characters, modifierFlags: flags) == nil)
  }
}
