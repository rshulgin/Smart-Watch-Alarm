import SwiftUI

struct SettingsView: View {
  @ObservedObject var settings: AppSettings

  var body: some View {
    List {
      Section("Motion Sensitivity") {
        Picker("Sensitivity", selection: $settings.motionSensitivity) {
          ForEach(AppSettings.MotionSensitivity.allCases, id: \.self) { level in
            Text(level.label).tag(level)
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      }

      Section("Haptic Intensity") {
        Picker("Intensity", selection: $settings.hapticIntensity) {
          ForEach(AppSettings.HapticIntensity.allCases, id: \.self) { level in
            Text(level.label).tag(level)
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      }
    }
    .navigationTitle("Settings")
  }
}

#Preview {
  NavigationStack {
    SettingsView(settings: AppSettings())
  }
}
