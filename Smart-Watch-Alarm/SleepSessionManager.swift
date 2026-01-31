import Foundation
import HealthKit

final class SleepSessionManager: ObservableObject {
  @Published private(set) var isMonitoring = false
  @Published private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined

  private let healthStore = HKHealthStore()

  func refreshAuthorizationStatus() {
    authorizationStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
  }

  func requestAuthorization(completion: @escaping (Bool) -> Void) {
    let workoutType = HKObjectType.workoutType()
    healthStore.requestAuthorization(toShare: [workoutType], read: [workoutType]) { [weak self] success, _ in
      DispatchQueue.main.async {
        self?.refreshAuthorizationStatus()
        completion(success)
      }
    }
  }

  func startMonitoring() {
    isMonitoring = true
  }

  func stopMonitoring() {
    isMonitoring = false
  }
}
