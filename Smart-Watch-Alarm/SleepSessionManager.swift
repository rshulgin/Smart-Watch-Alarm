import CoreMotion
import Foundation
import HealthKit

protocol HealthStoreAuthorizationProviding {
  func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
  func requestAuthorization(toShare typesToShare: Set<HKSampleType>?,
                            read typesToRead: Set<HKObjectType>?,
                            completion: @escaping (Bool, Error?) -> Void)
}

extension HKHealthStore: HealthStoreAuthorizationProviding {}

final class SleepSessionManager: NSObject, ObservableObject {
  @Published private(set) var isMonitoring = false
  @Published private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined

  private let healthStore: HKHealthStore
  private let authorizationStore: HealthStoreAuthorizationProviding
  private let motionManager = MotionManager()
  private var workoutSession: HKWorkoutSession?
  private var workoutBuilder: HKLiveWorkoutBuilder?
  private var latestAcceleration: CMAcceleration?
  private var lastMotionDetectedAt: Date?
  private let motionThreshold = 0.15

  init(healthStore: HKHealthStore = HKHealthStore(),
       authorizationStore: HealthStoreAuthorizationProviding? = nil) {
    self.healthStore = healthStore
    self.authorizationStore = authorizationStore ?? healthStore
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
    guard HKHealthStore.isHealthDataAvailable() else {
      return
    }

    if workoutSession != nil {
      return
    }

    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .mindAndBody
    configuration.locationType = .unknown

    do {
      let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
      let builder = session.associatedWorkoutBuilder()

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
    guard let session = workoutSession else {
      return
    }

    stopMotionUpdates()
    session.end()
    workoutBuilder?.endCollection(withEnd: Date()) { [weak self] _, _ in
      self?.workoutBuilder?.finishWorkout { _, _ in }
    }
  }

  private func startMotionUpdates() {
    motionManager.startUpdates { [weak self] data in
      DispatchQueue.main.async {
        self?.handleMotionData(data)
      }
    }
  }

  private func stopMotionUpdates() {
    motionManager.stopUpdates()
    latestAcceleration = nil
    lastMotionDetectedAt = nil
  }

  private func handleMotionData(_ data: CMAccelerometerData) {
    let current = data.acceleration

    if let previous = latestAcceleration {
      let deltaX = current.x - previous.x
      let deltaY = current.y - previous.y
      let deltaZ = current.z - previous.z
      let deltaMagnitude = sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)

      if deltaMagnitude >= motionThreshold {
        lastMotionDetectedAt = Date()
      }
    }

    latestAcceleration = current
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
