import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var sessionManager: SleepSessionManager
  @State private var didStart = false
  @State private var pulse = false

  var body: some View {
    GeometryReader { proxy in
      let size = min(proxy.size.width, proxy.size.height) * 0.8

      VStack(spacing: 8) {
        Button(action: { sessionManager.stopMonitoring() }) {
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
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .onAppear {
      startMonitoringIfPossible()
    }
    .onChange(of: sessionManager.isMonitoring) { isMonitoring in
      pulse = isMonitoring
    }
  }

  private func startMonitoringIfPossible() {
    guard !didStart else {
      return
    }

    didStart = true
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
}

#Preview {
  ContentView()
    .environmentObject(SleepSessionManager())
}
