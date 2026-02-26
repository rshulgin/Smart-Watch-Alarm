import Foundation

final class AppSettings: ObservableObject {
  static let shared = AppSettings()

  private enum Keys {
    static let motionSensitivity = "motionSensitivity"
    static let hapticIntensity = "hapticIntensity"
  }

  enum MotionSensitivity: String, CaseIterable {
    case low, medium, high

    /// Acceleration delta threshold (g-force). Lower value = more sensitive.
    var threshold: Double {
      switch self {
      case .low: return 0.30
      case .medium: return 0.15
      case .high: return 0.08
      }
    }

    var label: String { rawValue.capitalized }
  }

  enum HapticIntensity: String, CaseIterable {
    case low, medium, high

    /// Number of haptic pulses fired per trigger.
    var burstCount: Int {
      switch self {
      case .low: return 10
      case .medium: return 25
      case .high: return 50
      }
    }

    var label: String { rawValue.capitalized }
  }

  @Published var motionSensitivity: MotionSensitivity {
    didSet { UserDefaults.standard.set(motionSensitivity.rawValue, forKey: Keys.motionSensitivity) }
  }

  @Published var hapticIntensity: HapticIntensity {
    didSet { UserDefaults.standard.set(hapticIntensity.rawValue, forKey: Keys.hapticIntensity) }
  }

  init() {
    let storedSens = UserDefaults.standard.string(forKey: Keys.motionSensitivity) ?? ""
    motionSensitivity = MotionSensitivity(rawValue: storedSens) ?? .medium

    let storedHaptic = UserDefaults.standard.string(forKey: Keys.hapticIntensity) ?? ""
    hapticIntensity = HapticIntensity(rawValue: storedHaptic) ?? .medium
  }
}
