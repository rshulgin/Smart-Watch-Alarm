import CoreMotion
import Foundation
import HealthKit
import WatchKit

protocol HealthStoreAuthorizationProviding {
  func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
  func requestAuthorization(toShare typesToShare: Set<HKSampleType>?,
                            read typesToRead: Set<HKObjectType>?,
                            completion: @escaping (Bool, Error?) -> Void)
}

extension HKHealthStore: HealthStoreAuthorizationProviding {}

protocol HapticPlaying {
  func play(_ type: WKHapticType)
}

struct DefaultHapticPlayer: HapticPlaying {
  func play(_ type: WKHapticType) {
    WKInterfaceDevice.current().play(type)
  }
}

protocol WorkoutSessionBuilding: AnyObject {
  var delegate: HKLiveWorkoutBuilderDelegate? { get set }
  var dataSource: HKLiveWorkoutDataSource? { get set }
  func beginCollection(withStart startDate: Date, completion: @escaping (Bool, Error?) -> Void)
  func endCollection(withEnd endDate: Date, completion: @escaping (Bool, Error?) -> Void)
  func finishWorkout(completion: @escaping (HKWorkout?, Error?) -> Void)
}

extension HKLiveWorkoutBuilder: WorkoutSessionBuilding {}

protocol WorkoutSessioning: AnyObject {
  var delegate: HKWorkoutSessionDelegate? { get set }
  func startActivity(with date: Date?)
  func end()
  func makeWorkoutBuilder() -> WorkoutSessionBuilding
}

extension HKWorkoutSession: WorkoutSessioning {
  func makeWorkoutBuilder() -> WorkoutSessionBuilding {
    associatedWorkoutBuilder()
  }
}

protocol WorkoutSessionFactory {
  func makeSession(healthStore: HKHealthStore,
                   configuration: HKWorkoutConfiguration) throws -> WorkoutSessioning
}

struct HealthKitWorkoutSessionFactory: WorkoutSessionFactory {
  func makeSession(healthStore: HKHealthStore,
                   configuration: HKWorkoutConfiguration) throws -> WorkoutSessioning {
    try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
  }
}

class SleepSessionManager: NSObject, ObservableObject {
  @Published private(set) var isMonitoring = false
  @Published private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined
  @Published private(set) var isSessionEnded = false

  private let healthStore: HKHealthStore
  private let authorizationStore: HealthStoreAuthorizationProviding
  private let motionManager: MotionManager
  private let hapticPlayer: HapticPlaying
  private let workoutSessionFactory: WorkoutSessionFactory
  private let healthAvailabilityProvider: () -> Bool
  private let dateProvider: () -> Date
  private let hapticType: WKHapticType = .notification
  private var workoutSession: WorkoutSessioning?
  private var workoutBuilder: WorkoutSessionBuilding?
  private var latestAcceleration: CMAcceleration?
  private var lastMotionDetectedAt: Date?
  private var lastHapticTriggeredAt: Date?

  init(healthStore: HKHealthStore = HKHealthStore(),
       authorizationStore: HealthStoreAuthorizationProviding? = nil,
       motionManager: MotionManager = MotionManager(),
       hapticPlayer: HapticPlaying = DefaultHapticPlayer(),
       workoutSessionFactory: WorkoutSessionFactory = HealthKitWorkoutSessionFactory(),
       healthAvailabilityProvider: @escaping () -> Bool = HKHealthStore.isHealthDataAvailable,
       dateProvider: @escaping () -> Date = Date.init) {
    self.healthStore = healthStore
    self.authorizationStore = authorizationStore ?? healthStore
    self.motionManager = motionManager
    self.hapticPlayer = hapticPlayer
    self.workoutSessionFactory = workoutSessionFactory
    self.healthAvailabilityProvider = healthAvailabilityProvider
    self.dateProvider = dateProvider
    super.init()
  }

  func refreshAuthorizationStatus() {
    authorizationStatus = authorizationStore.authorizationStatus(for: HKObjectType.workoutType())
  }

  func requestAuthorization(completion: @escaping (Bool) -> Void) {
    let workoutType = HKObjectType.workoutType()
    authorizationStore.requestAuthorization(toShare: [workoutType], read: [workoutType]) { [weak self] success, _ in
      DispatchQueue.main.async {
        self?.refreshAuthorizationStatus()
        completion(success)
      }
    }
  }

  func startMonitoring() {
    guard healthAvailabilityProvider() else {
      return
    }

    if workoutSession != nil {
      return
    }

    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .mindAndBody
    configuration.locationType = .unknown

    do {
      let session = try workoutSessionFactory.makeSession(healthStore: healthStore, configuration: configuration)
      let builder = session.makeWorkoutBuilder()

      session.delegate = self
      builder.delegate = self
      builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

      workoutSession = session
      workoutBuilder = builder

      let startDate = Date()
      session.startActivity(with: startDate)
      builder.beginCollection(withStart: startDate) { [weak self] success, _ in
        DispatchQueue.main.async {
          self?.isMonitoring = success
          if success {
            self?.startMotionUpdates()
          }
        }
      }
    } catch {
      isMonitoring = false
    }
  }

  func stopMonitoring() {
    stopMotionUpdates()
    guard let session = workoutSession else {
      return
    }
    session.end()
    workoutBuilder?.endCollection(withEnd: Date()) { [weak self] _, _ in
      self?.workoutBuilder?.finishWorkout { _, _ in }
    }
  }

  func stopSession() {
    stopMonitoring()
    isMonitoring = false
    isSessionEnded = true
  }

  func setMonitoringForTesting(_ value: Bool) {
    isMonitoring = value
  }

  private func startMotionUpdates() {
    motionManager.startUpdates { [weak self] acceleration in
      DispatchQueue.main.async {
        self?.handleAcceleration(acceleration, at: SleepSessionManager.resolveDate(using: self))
      }
    }
  }

  static func resolveDate(using manager: SleepSessionManager?) -> Date {
    manager?.dateProvider() ?? Date()
  }

  private func stopMotionUpdates() {
    motionManager.stopUpdates()
    latestAcceleration = nil
    lastMotionDetectedAt = nil
    lastHapticTriggeredAt = nil
  }

  func handleAcceleration(_ acceleration: CMAcceleration, at date: Date) {
    if let previous = latestAcceleration {
      if detectMotion(previous: previous, current: acceleration) {
        if canTriggerHaptic(at: date) {
          hapticPlayer.play(hapticType)
          lastHapticTriggeredAt = date
        }
        lastMotionDetectedAt = date
      }
    }

    latestAcceleration = acceleration
  }

  func detectMotion(previous: CMAcceleration, current: CMAcceleration) -> Bool {
    let deltaX = current.x - previous.x
    let deltaY = current.y - previous.y
    let deltaZ = current.z - previous.z
    let deltaMagnitude = sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)

    return deltaMagnitude >= MotionConstants.motionThreshold
  }

  func canTriggerHaptic(at date: Date) -> Bool {
    guard let lastHapticTriggeredAt else {
      return true
    }

    return date.timeIntervalSince(lastHapticTriggeredAt) >= MotionConstants.motionCooldownSeconds
  }
}

extension SleepSessionManager: HKWorkoutSessionDelegate {
  func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      self?.stopMotionUpdates()
      self?.isMonitoring = false
    }
  }

  func workoutSession(_ workoutSession: HKWorkoutSession,
                      didChangeTo toState: HKWorkoutSessionState,
                      from fromState: HKWorkoutSessionState,
                      date: Date) {
    DispatchQueue.main.async { [weak self] in
      self?.isMonitoring = (toState == .running)

      if toState == .ended {
        self?.stopMotionUpdates()
        self?.workoutSession = nil
        self?.workoutBuilder = nil
      }
    }
  }
}

extension SleepSessionManager: HKLiveWorkoutBuilderDelegate {
  func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

  func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}
