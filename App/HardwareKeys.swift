import SwiftUI

/// What the keys of a hardware keyboard do: typing goes into the formula as the keys on the screen put it there, return starts
/// a new line (the next row in a matrix), Tab goes from cell to cell of a matrix, delete deletes and the arrows move.
///
/// Only ASCII and a few mathematical characters are taken, so that a keyboard layout or an input method for another script
/// does not put anything strange into a formula. `^` and `/` are typed as the characters they are, read with the right
/// precedence (`x^2+1` is x² + 1), and not as a power or a fraction to be filled in: with a keyboard one types a line, and a
/// structure that swallows what follows would make `1/2+3` mean `1/(2+3)`.
enum HardwareKeys {
  /// What a key press puts in, or `nil` for a press that is not for the calculator (a shortcut, a key it has no use for).
  static func actions(
    key: KeyEquivalent, characters: String, modifiers: EventModifiers, inMatrix: Bool
  ) -> [KeyAction]? {
    // Command and Control are for the shortcuts of the menus; Option is left alone because it makes the characters it
    // makes only when one means them (Option-P is π on a US keyboard).
    guard modifiers.isDisjoint(with: [.command, .control]) else { return nil }
    switch key {
    case .return: return [.newLine]
    case .delete: return [.backspace]
    case .leftArrow: return [.left]
    case .rightArrow: return [.right]
    case .tab:
      // Outside a matrix Tab is left to the system, which moves the focus with it.
      guard inMatrix else { return nil }
      return [modifiers.contains(.shift) ? .previousCell : .nextCell]
    default: break
    }
    let actions = characters.compactMap(action(for:))
    return actions.isEmpty ? nil : actions
  }

  /// What typing one character puts in, or `nil` for a character a formula has no use for.
  static func action(for character: Character) -> KeyAction? {
    switch character {
    case "-": return .symbol("−")
    case "*": return .symbol("×")
    case "[", "]", "{", "}", "|": return .literal(String(character))
    case "(", ")", "+", "=", "<", ">", "!", "%", ".", ",", ";", "^", "/", "°", "∞", "≠", "≤", "≥", "×", "÷", "−", "²",
      "³",
      "π":
      return .symbol(String(character))
    default:
      guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
      switch scalar.value {
      case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:  // 0–9, A–Z, a–z
        return .symbol(String(character))
      // The Greek letters, but not the unassigned 0x3A2 or the final sigma.
      case 0x391...0x3C9 where scalar.value != 0x3A2 && scalar.value != 0x3C2:
        return .symbol(String(character))
      default:
        return nil
      }
    }
  }
}

/// Makes a view take the typing of a hardware keyboard, and keeps the keyboard's focus on it: the calculator has no text
/// field, so the keys go to whatever has the focus, and this is what should.
struct HardwareKeyboardInput: ViewModifier {
  @Environment(AppModel.self) private var model
  @FocusState private var hasFocus: Bool

  func body(content: Content) -> some View {
    content
      .focusable()
      .focused($hasFocus)
      .focusEffectDisabled()
      .onKeyPress(phases: [.down, .repeat]) { press in
        guard
          let actions = HardwareKeys.actions(
            key: press.key, characters: press.characters, modifiers: press.modifiers, inMatrix: model.editor.isInMatrix)
        else { return .ignored }
        model.press(actions)
        return .handled
      }
      .task { hasFocus = true }
      // A sheet or a popover takes the focus; when it goes the typing has to come back.
      .onChange(of: model.showsHistory) { if !$1 { hasFocus = true } }
      .onChange(of: model.showsSettings) { if !$1 { hasFocus = true } }
  }
}

extension View {
  func takesHardwareKeyboardInput() -> some View { modifier(HardwareKeyboardInput()) }
}
