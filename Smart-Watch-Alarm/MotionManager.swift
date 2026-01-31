import CoreMotion

final class MotionManager {
  private let motionManager: CMMotionManager
  private let queue: OperationQueue

  init(updateInterval: TimeInterval = 1.0) {
    motionManager = CMMotionManager()
    motionManager.accelerometerUpdateInterval = updateInterval

    queue = OperationQueue()
    queue.name = "MotionManagerQueue"
  }

  var isAvailable: Bool {
    motionManager.isAccelerometerAvailable
  }

  var isActive: Bool {
    motionManager.isAccelerometerActive
  }

  func startUpdates(handler: @escaping (CMAccelerometerData) -> Void) {
    guard isAvailable, !isActive else {
      return
    }

    motionManager.startAccelerometerUpdates(to: queue) { data, _ in
      guard let data else {
        return
      }

      handler(data)
    }
  }

  func stopUpdates() {
    motionManager.stopAccelerometerUpdates()
  }
}
