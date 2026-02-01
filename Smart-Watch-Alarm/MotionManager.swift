import CoreMotion

protocol MotionManagerProviding {
  var isAccelerometerAvailable: Bool { get }
  var isAccelerometerActive: Bool { get }
  var accelerometerUpdateInterval: TimeInterval { get set }
  func startAccelerometerUpdates(to queue: OperationQueue,
                                 withHandler handler: @escaping (CMAccelerometerData?, Error?) -> Void)
  func stopAccelerometerUpdates()
}

extension CMMotionManager: MotionManagerProviding {}

final class MotionManager {
  private var motionManager: MotionManagerProviding
  private let queue: OperationQueue
  var testAcceleration: CMAcceleration?

  init(updateInterval: TimeInterval = MotionConstants.updateInterval,
       motionManager: MotionManagerProviding = CMMotionManager()) {
    self.motionManager = motionManager
    self.motionManager.accelerometerUpdateInterval = updateInterval

    queue = OperationQueue()
    queue.name = "MotionManagerQueue"
  }

  var isAvailable: Bool {
    motionManager.isAccelerometerAvailable
  }

  var isActive: Bool {
    motionManager.isAccelerometerActive
  }

  func startUpdates(handler: @escaping (CMAcceleration) -> Void) {
    guard isAvailable, !isActive else {
      return
    }

    motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
      self?.handleUpdate(acceleration: data?.acceleration, handler: handler)
    }

    if let testAcceleration {
      handleUpdate(acceleration: testAcceleration, handler: handler)
    }
  }

  func stopUpdates() {
    motionManager.stopAccelerometerUpdates()
  }

  func handleUpdate(acceleration: CMAcceleration?,
                    handler: @escaping (CMAcceleration) -> Void) {
    guard let acceleration else {
      return
    }

    handler(acceleration)
  }
}
