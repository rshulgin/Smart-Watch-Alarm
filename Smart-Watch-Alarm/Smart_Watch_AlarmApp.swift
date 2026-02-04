import SwiftUI
import WatchKit

final class ExtensionDelegate: NSObject, WKExtensionDelegate {
  func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    for task in backgroundTasks {
      switch task {
      case let refreshTask as WKApplicationRefreshBackgroundTask:
        AlarmCoordinator.shared.handleBackgroundRefresh(sessionManager: SleepSessionManager.shared)
        refreshTask.setTaskCompletedWithSnapshot(false)
      default:
        task.setTaskCompletedWithSnapshot(false)
      }
    }
  }
}

@main
struct Smart_Watch_AlarmApp: App {
  @WKExtensionDelegateAdaptor(ExtensionDelegate.self) private var extensionDelegate
  @StateObject private var sessionManager = SleepSessionManager.shared

  var body: some Scene {
    WindowGroup {
      ContentView(sessionManager: sessionManager)
    }
  }
}
