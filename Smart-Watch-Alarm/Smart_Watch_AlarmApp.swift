import SwiftUI

@main
struct Smart_Watch_AlarmApp: App {
  @StateObject private var sessionManager = SleepSessionManager.shared

  var body: some Scene {
    WindowGroup {
      ContentView(sessionManager: sessionManager)
    }
  }
}
