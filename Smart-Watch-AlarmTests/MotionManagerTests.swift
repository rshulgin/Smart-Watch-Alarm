import XCTest
import CoreMotion
@testable import Smart_Watch_Alarm

final class MotionManagerTests: XCTestCase {
  func testStartUpdatesReturnsEarlyWhenUnavailable() {
    let provider = TestMotionProvider()
    provider.isAccelerometerAvailable = false
    let manager = MotionManager(updateInterval: 0.1, motionManager: provider)

    manager.startUpdates { _ in }

    XCTAssertFalse(provider.startCalled)
  }

  func testStartUpdatesReturnsEarlyWhenActive() {
    let provider = TestMotionProvider()
    provider.isAccelerometerActive = true
    let manager = MotionManager(updateInterval: 0.1, motionManager: provider)

    manager.startUpdates { _ in }

    XCTAssertFalse(provider.startCalled)
  }

  func testStartUpdatesCallsUnderlyingProvider() {
    let provider = TestMotionProvider()
    let manager = MotionManager(updateInterval: 0.1, motionManager: provider)

    manager.startUpdates { _ in }

    XCTAssertTrue(provider.startCalled)
  }

  func testHandleUpdateWithNilDoesNotInvokeHandler() {
    let provider = TestMotionProvider()
    let manager = MotionManager(updateInterval: 0.1, motionManager: provider)
    var invoked = false

    manager.handleUpdate(acceleration: nil) { _ in
      invoked = true
    }

    XCTAssertFalse(invoked)
  }

  func testHandleUpdateWithAccelerationInvokesHandler() {
    let provider = TestMotionProvider()
    let manager = MotionManager(updateInterval: 0.1, motionManager: provider)
    let expected = CMAcceleration(x: 1, y: 2, z: 3)
    var received: CMAcceleration?

    manager.handleUpdate(acceleration: expected) { acceleration in
      received = acceleration
    }

    XCTAssertEqual(received?.x, expected.x)
    XCTAssertEqual(received?.y, expected.y)
    XCTAssertEqual(received?.z, expected.z)
  }

  func testStopUpdatesCallsUnderlyingProvider() {
    let provider = TestMotionProvider()
    let manager = MotionManager(updateInterval: 0.1, motionManager: provider)

    manager.stopUpdates()

    XCTAssertTrue(provider.stopCalled)
  }

  func testStartUpdatesUsesTestAcceleration() {
    let provider = TestMotionProvider()
    let manager = MotionManager(updateInterval: 0.1, motionManager: provider)
    manager.testAcceleration = CMAcceleration(x: 1, y: 0, z: 0)
    var invoked = false

    manager.startUpdates { _ in
      invoked = true
    }

    XCTAssertTrue(invoked)
  }
}

private final class TestMotionProvider: MotionManagerProviding {
  var isAccelerometerAvailable: Bool = true
  var isAccelerometerActive: Bool = false
  var accelerometerUpdateInterval: TimeInterval = 0
  private(set) var startCalled = false
  private(set) var stopCalled = false

  func startAccelerometerUpdates(to queue: OperationQueue,
                                 withHandler handler: @escaping (CMAccelerometerData?, Error?) -> Void) {
    startCalled = true
    handler(nil, nil)
  }

  func stopAccelerometerUpdates() {
    stopCalled = true
  }
}
