import MantissaCore
import SwiftUI

/// The language the app shows itself in: the system's, or one chosen here.
enum AppLanguage: String, CaseIterable, Identifiable {
  case system
  case english
  case japanese

  var id: Self { self }

  /// The locale to give the views, or `nil` to follow the system.
  var locale: Locale? {
    switch self {
    case .system: return nil
    case .english: return Locale(identifier: "en")
    case .japanese: return Locale(identifier: "ja")
    }
  }

  /// The bundle that holds the strings of this language.
  var bundle: Bundle {
    let code: String
    switch self {
    case .system: return .main
    case .english: code = "en"
    case .japanese: code = "ja"
    }
    guard let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else {
      return .main
    }
    return bundle
  }
}

/// Looks strings up in the language chosen in the app, for text that is not a SwiftUI view (the history keeps a few words).
enum Localizer {
  nonisolated(unsafe) static var bundle = Bundle.main

  static func string(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
  }
}

/// What the user has chosen in Settings, kept in the app's own defaults. Nothing leaves the phone.
struct SettingsStorage {
  var defaults: UserDefaults = .standard

  private enum Key {
    static let angleUnit = "angleUnit"
    static let digits = "decimalDigits"
    static let language = "language"
  }

  var angleUnit: AngleUnit {
    get { defaults.string(forKey: Key.angleUnit) == "degrees" ? .degrees : .radians }
    nonmutating set { defaults.set(newValue == .degrees ? "degrees" : "radians", forKey: Key.angleUnit) }
  }

  var decimalDigits: Int {
    get {
      let stored = defaults.integer(forKey: Key.digits)
      return stored == 0 ? 12 : min(max(stored, 4), 50)
    }
    nonmutating set { defaults.set(newValue, forKey: Key.digits) }
  }

  var language: AppLanguage {
    get { AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system }
    nonmutating set { defaults.set(newValue.rawValue, forKey: Key.language) }
  }
}
