import SwiftUI

@main
struct Smart_Watch_AlarmApp: App {
  @StateObject private var sessionManager = SleepSessionManager.shared
  @StateObject private var settings = AppSettings.shared

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        ContentView(sessionManager: sessionManager, settings: settings)
      }
    }
  }
}
