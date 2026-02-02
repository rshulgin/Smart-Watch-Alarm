import SwiftUI

struct ContentView: View {
  @ObservedObject var sessionManager: SleepSessionManager
  @State private var pulse = false
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    GeometryReader { proxy in
      bodyContent(size: min(proxy.size.width, proxy.size.height) * 0.8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .onAppear(perform: handleAppear)
    .onChange(of: sessionManager.isMonitoring) { oldValue, newValue in
      handleMonitoringChange(newValue)
    }
    .onChange(of: scenePhase) { oldValue, newValue in
      handleScenePhaseChange(newValue)
    }
  }

  @ViewBuilder
  func bodyContent(size: CGFloat) -> some View {
    if sessionManager.isSessionEnded {
      SessionEndedView()
    } else {
      VStack(spacing: 8) {
        Button(action: handleStopTapped) {
          ZStack {
            Circle()
              .fill(Color.red)
            Text("STOP")
              .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
              .foregroundColor(.white)
          }
          .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .overlay(
          Circle()
            .stroke(Color.red.opacity(0.6), lineWidth: 4)
            .scaleEffect(pulse ? 1.08 : 0.92)
            .opacity(pulse ? 0.15 : 0.7)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            .frame(width: size, height: size)
            .opacity(sessionManager.isMonitoring ? 1 : 0)
        )

        Text(statusText)
          .font(.footnote)
          .foregroundColor(statusColor)

        if statusHintText != nil {
          Text(statusHintText ?? "")
            .font(.footnote)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }

        if shouldShowRetry {
          Button("Retry") {
            sessionManager.retryAuthorization()
          }
          .font(.footnote)
          .buttonStyle(.bordered)
        }
      }
    }
  }

  var statusText: String {
    switch sessionManager.status {
    case .monitoring:
      return "Monitoring..."
    case .needsAuthorization:
      return "Health access required"
    case .healthUnavailable:
      return "Health unavailable"
    case .motionUnavailable:
      return "Motion unavailable"
    case .failed:
      return "Failed to start"
    case .ended:
      return "Session ended"
    case .starting:
      return "Starting..."
    }
  }

  var statusColor: Color {
    switch sessionManager.status {
    case .needsAuthorization:
      return .orange
    case .healthUnavailable, .motionUnavailable, .failed:
      return .red
    default:
      return .secondary
    }
  }

  var shouldShowRetry: Bool {
    switch sessionManager.status {
    case .needsAuthorization, .failed:
      return true
    default:
      return false
    }
  }

  var statusHintText: String? {
    switch sessionManager.status {
    case .needsAuthorization:
      return "If no prompt appears, open iPhone Health and allow access for this app."
    default:
      return nil
    }
  }

  func handleAppear() {
    sessionManager.attemptStart()
  }

  func handleScenePhaseChange(_ newPhase: ScenePhase) {
    if newPhase == .active {
      sessionManager.attemptStart()
    }
  }

  func handleMonitoringChange(_ newValue: Bool) {
    pulse = newValue
  }

  func handleStopTapped() {
    sessionManager.stopSession()
  }
}

struct SessionEndedView: View {
  var body: some View {
    VStack(spacing: 8) {
      Text("Session Ended")
        .font(.headline)
      Text("Monitoring stopped")
        .font(.footnote)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }
}

#Preview {
  ContentView(sessionManager: SleepSessionManager())
}
