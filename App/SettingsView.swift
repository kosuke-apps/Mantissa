import MantissaCore
import SwiftUI

/// Angle unit, number of digits, language, and what the app is.
struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  private let digitChoices = [6, 8, 10, 12, 15, 20, 30]

  var body: some View {
    @Bindable var model = model
    NavigationStack {
      Form {
        Section {
          Picker("Angle unit", selection: $model.angleUnit) {
            Text("Radians").tag(AngleUnit.radians)
            Text("Degrees").tag(AngleUnit.degrees)
          }
          .pickerStyle(.segmented)
        } header: {
          Text("Angles")
        } footer: {
          Text(
            "The degree sign always means degrees: cos(30°) is the same in both. Without it, cos(30) follows this setting."
          )
        }

        Section("Decimals") {
          Picker("Significant digits", selection: $model.decimalDigits) {
            ForEach(digitChoices, id: \.self) { Text("\($0)").tag($0) }
          }
        }

        Section("Language") {
          Picker("Language", selection: $model.language) {
            Text("System default").tag(AppLanguage.system)
            Text(verbatim: "English").tag(AppLanguage.english)
            Text(verbatim: "日本語").tag(AppLanguage.japanese)
          }
        }

        Section {
          LabeledContent("Version", value: Self.version)
          NavigationLink("License") { LicenseView() }
        } header: {
          Text("About")
        } footer: {
          Text(
            "Everything is worked out on this phone. Nothing is sent anywhere, and there are no accounts, ads or tracking."
          )
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
  }

  private static var version: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(short) (\(build))"
  }
}

private struct LicenseView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text(verbatim: "Mantissa").font(.headline)
        Text(verbatim: "Copyright © 2026 Kosuke Satake")
        Text(
          "Mantissa is free software under the MIT License. It uses no third-party code: the number types, the algebra and the graphing are written for it."
        )
        Text(verbatim: Self.mit).font(.footnote).foregroundStyle(.secondary)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("License")
    .navigationBarTitleDisplayMode(.inline)
  }

  private static let mit = """
    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated \
    documentation files (the "Software"), to deal in the Software without restriction, including without limitation the \
    rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit \
    persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the \
    Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE \
    WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR \
    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR \
    OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}
