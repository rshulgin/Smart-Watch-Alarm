import XCTest
import CoreMotion
@testable import Smart_Watch_Alarm

final class MotionDetectionTests: XCTestCase {
  func testDetectMotionReturnsFalseBelowThreshold() {
    let manager = SleepSessionManager()
    let previous = CMAcceleration(x: 0, y: 0, z: 0)
    let current = CMAcceleration(x: MotionConstants.motionThreshold * 0.5, y: 0, z: 0)

    XCTAssertFalse(manager.detectMotion(previous: previous, current: current))
  }

  func testDetectMotionReturnsTrueAtThreshold() {
    let manager = SleepSessionManager()
    let previous = CMAcceleration(x: 0, y: 0, z: 0)
    let current = CMAcceleration(x: MotionConstants.motionThreshold, y: 0, z: 0)

    XCTAssertTrue(manager.detectMotion(previous: previous, current: current))
  }

  func testDetectMotionCombinesAxes() {
    let manager = SleepSessionManager()
    let previous = CMAcceleration(x: 0, y: 0, z: 0)
    let component = MotionConstants.motionThreshold / sqrt(3) * 1.1
    let current = CMAcceleration(x: component, y: component, z: component)

    XCTAssertTrue(manager.detectMotion(previous: previous, current: current))
  }
}
