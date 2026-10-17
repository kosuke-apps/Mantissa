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
  }
}
