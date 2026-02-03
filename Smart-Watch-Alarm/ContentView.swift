import SwiftUI

struct ContentView: View {
  @ObservedObject var sessionManager: SleepSessionManager
  @State private var pulse = false
  @State private var selectedTime = Date()
  @State private var countdownRemaining: TimeInterval?
  @State private var countdownTarget: Date?
  @State private var isCountdownActive = false
  @State private var didInitiateStart = false
  @Environment(\.scenePhase) private var scenePhase
  private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    GeometryReader { proxy in
      bodyContent(size: min(proxy.size.width, proxy.size.height) * 0.8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .onChange(of: sessionManager.isMonitoring) { oldValue, newValue in
      handleMonitoringChange(newValue)
    }
    .onChange(of: scenePhase) { oldValue, newValue in
      handleScenePhaseChange(newValue)
    }
    .onReceive(countdownTimer) { _ in
      handleCountdownTick()
    }
  }

  @ViewBuilder
  func bodyContent(size: CGFloat) -> some View {
    if sessionManager.isSessionEnded {
      SessionEndedView()
    } else {
      VStack(spacing: 8) {
        DatePicker("Alarm time", selection: $selectedTime, displayedComponents: .hourAndMinute)
          .labelsHidden()
          .datePickerStyle(.wheel)
          .environment(\.locale, Locale(identifier: "en_GB"))
          .disabled(isCountdownActive || sessionManager.isMonitoring)

        if let countdownText {
          Text(countdownText)
            .font(.footnote)
            .foregroundColor(.secondary)
        }

        Button(action: handlePrimaryTapped) {
          ZStack {
            Circle()
              .fill(primaryButtonColor)
            Text(primaryButtonTitle)
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
        .disabled(isCountdownActive && !sessionManager.isMonitoring)

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
    if isCountdownActive {
      return "Counting down..."
    }

    if didInitiateStart && sessionManager.status == .starting {
      return "Starting..."
    }

    if !sessionManager.isMonitoring && !hasStatusError {
      return "Set alarm time"
    }

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
    if isCountdownActive {
      return .secondary
    }

    if !sessionManager.isMonitoring && !hasStatusError {
      return .secondary
    }

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

  var hasStatusError: Bool {
    switch sessionManager.status {
    case .needsAuthorization, .healthUnavailable, .motionUnavailable, .failed:
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

  func handleScenePhaseChange(_ newPhase: ScenePhase) {
    if newPhase == .active {
      if isCountdownActive {
        refreshCountdown()
      }
    }
  }

  func handleMonitoringChange(_ newValue: Bool) {
    pulse = newValue
  }

  func handleStopTapped() {
    sessionManager.stopSession()
  }

  var countdownText: String? {
    guard let remaining = countdownRemaining else {
      return nil
    }
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = remaining >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
    formatter.unitsStyle = .positional
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: max(0, remaining))
  }

  var primaryButtonTitle: String {
    sessionManager.isMonitoring ? "STOP" : "START"
  }

  var primaryButtonColor: Color {
    sessionManager.isMonitoring ? .red : .green
  }

  func handlePrimaryTapped() {
    if sessionManager.isMonitoring {
      handleStopTapped()
    } else {
      handleStartTapped()
    }
  }

  func handleStartTapped() {
    guard !isCountdownActive else {
      return
    }

    let now = Date()
    let target = nextTriggerDate(from: selectedTime, now: now)
    countdownTarget = target
    countdownRemaining = target.timeIntervalSince(now)
    isCountdownActive = true
    didInitiateStart = true
  }

  func nextTriggerDate(from selectedTime: Date, now: Date) -> Date {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.hour, .minute], from: selectedTime)
    var targetComponents = calendar.dateComponents([.year, .month, .day], from: now)
    targetComponents.hour = components.hour
    targetComponents.minute = components.minute
    targetComponents.second = 0

    let candidate = calendar.date(from: targetComponents) ?? now
    if candidate <= now {
      return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
    }
    return candidate
  }

  func handleCountdownTick() {
    guard isCountdownActive else {
      return
    }
    refreshCountdown()
  }

  func refreshCountdown() {
    guard let target = countdownTarget else {
      isCountdownActive = false
      countdownRemaining = nil
      return
    }

    let remaining = target.timeIntervalSince(Date())
    if remaining <= 0 {
      countdownRemaining = 0
      isCountdownActive = false
      sessionManager.attemptStart()
    } else {
      countdownRemaining = remaining
    }
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
