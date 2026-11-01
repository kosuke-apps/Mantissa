import SwiftUI

@main
struct MantissaApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      CalculatorScreen()
        .environment(model)
        .environment(\.locale, model.language.locale ?? Locale.current)
    }
    .commands {
      // Copy takes the answer and Paste puts a formula in, as the menus on the screen do; they stand in for the ones of a text
      // field, which the calculator does not have.
      CommandGroup(replacing: .pasteboard) {
        Button("Copy") { model.copyAnswerOrInput() }.keyboardShortcut("c")
        Button("Paste") { model.paste() }.keyboardShortcut("v")
      }
      CommandGroup(replacing: .appSettings) {
        Button("Settings") { model.showsSettings = true }.keyboardShortcut(",")
      }
      CommandGroup(before: .toolbar) {
        Button("History") { model.showsHistory.toggle() }.keyboardShortcut("y")
      }
    }
  }
}
