import CoreMotion
import Foundation
import HealthKit
import os
import WatchKit

private let logger = Logger(subsystem: "com.app.smart-watch-alarm", category: "SleepSession")

protocol HealthStoreAuthorizationProviding {
  func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
  func requestAuthorization(toShare typesToShare: Set<HKSampleType>?,
                            read typesToRead: Set<HKObjectType>?,
                            completion: @escaping @Sendable (Bool, Error?) -> Void)
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

protocol HapticScheduling {
  func schedule(after delay: TimeInterval, _ block: @escaping () -> Void)
}

struct MainHapticScheduler: HapticScheduling {
  func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
  }
}

enum MonitoringStatus: Equatable {
  case starting
  case monitoring
  case needsAuthorization
  case healthUnavailable
  case motionUnavailable
  case failed
  case ended
}

protocol WorkoutSessionBuilding: AnyObject {
  func beginCollection(withStart startDate: Date, completion: @escaping @Sendable (Bool, Error?) -> Void)
  func endCollection(withEnd endDate: Date, completion: @escaping @Sendable (Bool, Error?) -> Void)
  func finishWorkout(completion: @escaping @Sendable (HKWorkout?, Error?) -> Void)
  var delegate: HKLiveWorkoutBuilderDelegate? { get set }
  var dataSource: HKLiveWorkoutDataSource? { get set }
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
  static let shared = SleepSessionManager()

  @Published private(set) var isMonitoring = false
  @Published private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined
  @Published private(set) var isSessionEnded = false
  @Published private(set) var status: MonitoringStatus = .starting

  private let healthStore: HKHealthStore
  private let authorizationStore: HealthStoreAuthorizationProviding
  private let motionManager: MotionManager
  private let hapticPlayer: HapticPlaying
  private let hapticScheduler: HapticScheduling
  private let workoutSessionFactory: WorkoutSessionFactory
  private let healthAvailabilityProvider: () -> Bool
  private let dateProvider: () -> Date
  private let hapticType: WKHapticType = .failure
  private let hapticPattern: [WKHapticType]
  private let settings: AppSettings
  private var workoutSession: WorkoutSessioning?
  private var workoutBuilder: WorkoutSessionBuilding?
  private var latestAcceleration: CMAcceleration?
  private var lastMotionDetectedAt: Date?
  private var lastHapticTriggeredAt: Date?
  private var hapticsNotBefore: Date?
  private var isStarting = false
  private var isHapticBurstActive = false

  init(healthStore: HKHealthStore = HKHealthStore(),
       authorizationStore: HealthStoreAuthorizationProviding? = nil,
       motionManager: MotionManager = MotionManager(),
       hapticPlayer: HapticPlaying = DefaultHapticPlayer(),
       hapticScheduler: HapticScheduling = MainHapticScheduler(),
       hapticPattern: [WKHapticType] = [.failure, .notification],
       workoutSessionFactory: WorkoutSessionFactory = HealthKitWorkoutSessionFactory(),
       healthAvailabilityProvider: @escaping () -> Bool = HKHealthStore.isHealthDataAvailable,
       dateProvider: @escaping () -> Date = Date.init,
       settings: AppSettings = .shared) {
    self.healthStore = healthStore
    self.authorizationStore = authorizationStore ?? healthStore
    self.motionManager = motionManager
    self.hapticPlayer = hapticPlayer
    self.hapticScheduler = hapticScheduler
    self.hapticPattern = hapticPattern
    self.workoutSessionFactory = workoutSessionFactory
    self.healthAvailabilityProvider = healthAvailabilityProvider
    self.dateProvider = dateProvider
    self.settings = settings
    super.init()
  }

  func refreshAuthorizationStatus() {
    authorizationStatus = authorizationStore.authorizationStatus(for: HKObjectType.workoutType())
  }

  func attemptStart() {
    guard !isSessionEnded else {
      return
    }

    if isMonitoring {
      status = .monitoring
      return
    }

    guard !isStarting else {
      return
    }

    refreshAuthorizationStatus()

    switch authorizationStatus {
    case .sharingAuthorized:
      isStarting = true
      startMonitoring()
    case .notDetermined:
      isStarting = true
      status = .starting
      requestAuthorization { [weak self] success in
        guard let self else {
          return
        }
        if success {
          self.startMonitoring()
        } else {
          self.isStarting = false
          self.status = .needsAuthorization
        }
      }
    case .sharingDenied:
      status = .needsAuthorization
    @unknown default:
      status = .needsAuthorization
    }
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

  func retryAuthorization() {
    guard !isSessionEnded else {
      return
    }

    refreshAuthorizationStatus()
    if authorizationStatus == .sharingAuthorized {
      startMonitoring()
      return
    }

    isStarting = true
    status = .starting
    requestAuthorization { [weak self] success in
      guard let self else {
        return
      }
      if success {
        self.startMonitoring()
      } else {
        self.isStarting = false
        self.status = .needsAuthorization
      }
    }
  }

  func startMonitoring() {
    logger.info("startMonitoring called")
    status = .starting
    guard healthAvailabilityProvider() else {
      logger.warning("Health data unavailable")
      status = .healthUnavailable
      isStarting = false
      return
    }

    if workoutSession != nil {
      isStarting = false
      return
    }

    guard motionManager.isAvailable else {
      logger.warning("Motion manager unavailable")
      status = .motionUnavailable
      isStarting = false
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
            logger.info("Monitoring started successfully")
            self?.status = .monitoring
            self?.startMotionUpdates()
          } else {
            logger.error("beginCollection failed")
            self?.status = .failed
          }
          self?.isStarting = false
        }
      }
    } catch {
      logger.error("Failed to create workout session: \(error.localizedDescription)")
      isMonitoring = false
      status = .failed
      isStarting = false
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
    logger.info("stopSession called")
    stopMonitoring()
    isMonitoring = false
    isSessionEnded = true
    status = .ended
  }

  func resetSession() {
    logger.info("resetSession called")
    isSessionEnded = false
    isMonitoring = false
    isStarting = false
    status = .starting
    workoutSession = nil
    workoutBuilder = nil
    latestAcceleration = nil
    lastMotionDetectedAt = nil
    lastHapticTriggeredAt = nil
    hapticsNotBefore = nil
    isHapticBurstActive = false
  }

  func setHapticsNotBefore(_ date: Date?) {
    hapticsNotBefore = date
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
    isHapticBurstActive = false
  }

  func handleAcceleration(_ acceleration: CMAcceleration, at date: Date) {
    if let previous = latestAcceleration {
      if detectMotion(previous: previous, current: acceleration) {
        if canTriggerHaptic(at: date) && !isHapticBurstActive {
          triggerHapticBurst(at: date)
        }
        lastMotionDetectedAt = date
      }
    }

    latestAcceleration = acceleration
  }

  private func triggerHapticBurst(at date: Date) {
    isHapticBurstActive = true
    lastHapticTriggeredAt = date

    let pattern = hapticPattern.isEmpty ? [hapticType] : hapticPattern
    let burstCount = max(settings.hapticIntensity.burstCount, pattern.count)
    logger.info("Triggering haptic burst: \(burstCount) pulses")
    for index in 0..<burstCount {
      let delay = TimeInterval(index) * MotionConstants.hapticBurstInterval
      hapticScheduler.schedule(after: delay) { [weak self] in
        guard let self else {
          return
        }
        let type = pattern[index % pattern.count]
        self.hapticPlayer.play(type)
        if index == burstCount - 1 {
          self.isHapticBurstActive = false
        }
      }
    }
  }

  func detectMotion(previous: CMAcceleration, current: CMAcceleration) -> Bool {
    let deltaX = current.x - previous.x
    let deltaY = current.y - previous.y
    let deltaZ = current.z - previous.z
    let deltaMagnitude = sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)

    return deltaMagnitude >= settings.motionSensitivity.threshold
  }

  func canTriggerHaptic(at date: Date) -> Bool {
    if let hapticsNotBefore, date < hapticsNotBefore {
      return false
    }

    guard let lastHapticTriggeredAt else {
      return true
    }

    return date.timeIntervalSince(lastHapticTriggeredAt) >= MotionConstants.motionCooldownSeconds
  }
}

extension SleepSessionManager: HKWorkoutSessionDelegate {
  func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    logger.error("Workout session failed: \(error.localizedDescription)")
    DispatchQueue.main.async { [weak self] in
      self?.stopMotionUpdates()
      self?.isMonitoring = false
      self?.status = .failed
      self?.isStarting = false
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
        self?.status = self?.isSessionEnded == true ? .ended : .failed
        self?.isStarting = false
      } else if toState == .running {
        self?.status = .monitoring
        self?.isStarting = false
      }
    }
  }
}

extension SleepSessionManager: HKLiveWorkoutBuilderDelegate {
  func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

  func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}

struct AlarmSchedule {
  let target: Date
}

final class AlarmCoordinator {
  static let shared = AlarmCoordinator()

  private let targetKey = "alarmTargetTimestamp"

  @discardableResult
  func schedule(target: Date) -> AlarmSchedule {
    let schedule = AlarmSchedule(target: target)

    UserDefaults.standard.set(target.timeIntervalSince1970, forKey: targetKey)

    return schedule
  }

  func loadSchedule() -> AlarmSchedule? {
    let targetTimestamp = UserDefaults.standard.double(forKey: targetKey)
    guard targetTimestamp > 0 else {
      return nil
    }
    let target = Date(timeIntervalSince1970: targetTimestamp)
    return AlarmSchedule(target: target)
  }

  func clearSchedule() {
    UserDefaults.standard.removeObject(forKey: targetKey)
  }
}
