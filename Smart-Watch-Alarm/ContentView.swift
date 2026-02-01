import SwiftUI

struct ContentView: View {
  @ObservedObject var sessionManager: SleepSessionManager
  @State private var didStart = false
  @State private var pulse = false

  init(sessionManager: SleepSessionManager, didStart: Bool = false, pulse: Bool = false) {
    self.sessionManager = sessionManager
    _didStart = State(initialValue: didStart)
    _pulse = State(initialValue: pulse)
  }

  var body: some View {
    GeometryReader { proxy in
      bodyContent(size: min(proxy.size.width, proxy.size.height) * 0.8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .onAppear(perform: handleAppear)
    .onChange(of: sessionManager.isMonitoring, perform: handleMonitoringChange)
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

        Text(sessionManager.isMonitoring ? "Monitoring..." : "Starting...")
          .font(.footnote)
          .foregroundColor(.secondary)
      }
    }
  }

  func startMonitoringIfPossible() {
    guard !didStart else {
      return
    }

    didStart = true
    if sessionManager.isSessionEnded {
      return
    }
    sessionManager.refreshAuthorizationStatus()

    switch sessionManager.authorizationStatus {
    case .sharingAuthorized:
      sessionManager.startMonitoring()
    case .notDetermined:
      sessionManager.requestAuthorization { success in
        if success {
          sessionManager.startMonitoring()
        }
      }
    default:
      break
    }
  }

  func handleAppear() {
    startMonitoringIfPossible()
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
