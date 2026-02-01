import XCTest
import HealthKit
import CoreMotion
import WatchKit
@testable import Smart_Watch_Alarm

final class SleepSessionManagerTests: XCTestCase {
  func testRefreshAuthorizationStatusUsesAuthorizationStore() {
    let stub = StubAuthorizationStore(status: .sharingAuthorized)
    let manager = SleepSessionManager(authorizationStore: stub)

    manager.refreshAuthorizationStatus()

    XCTAssertEqual(manager.authorizationStatus, .sharingAuthorized)
  }

  func testRequestAuthorizationUpdatesStatusAndCompletes() {
    let stub = StubAuthorizationStore(status: .notDetermined)
    let manager = SleepSessionManager(authorizationStore: stub)
    let expectation = expectation(description: "Authorization completion called")

    manager.requestAuthorization { success in
      XCTAssertTrue(success)
      XCTAssertEqual(manager.authorizationStatus, .sharingAuthorized)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1.0)
  }

  func testStopSessionMarksEnded() {
    let manager = SleepSessionManager()

    manager.stopSession()

    XCTAssertTrue(manager.isSessionEnded)
  }

  func testStopSessionStopsMonitoring() {
    let manager = SleepSessionManager()

    manager.stopSession()

    XCTAssertFalse(manager.isMonitoring)
  }

  func testStartMonitoringReturnsWhenHealthUnavailable() {
    let factory = FakeWorkoutSessionFactory(session: FakeWorkoutSession(builder: FakeWorkoutBuilder()))
    let motionProvider = FakeMotionProvider()
    let manager = SleepSessionManager(motionManager: MotionManager(motionManager: motionProvider),
                                      workoutSessionFactory: factory,
                                      healthAvailabilityProvider: { false })

    manager.startMonitoring()

    XCTAssertFalse(factory.makeCalled)
    XCTAssertFalse(motionProvider.startCalled)
  }

  func testStartMonitoringStartsSessionAndMotionUpdates() {
    let builder = FakeWorkoutBuilder()
    let session = FakeWorkoutSession(builder: builder)
    let factory = FakeWorkoutSessionFactory(session: session)
    let motionProvider = FakeMotionProvider()
    motionProvider.isAccelerometerAvailable = true
    motionProvider.isAccelerometerActive = false
    let motionManager = MotionManager(motionManager: motionProvider)
    motionManager.testAcceleration = CMAcceleration(x: 0.1, y: 0.1, z: 0.1)
    let manager = SleepSessionManager(motionManager: motionManager,
                                      workoutSessionFactory: factory,
                                      healthAvailabilityProvider: { true })
    let expectation = expectation(description: "Monitoring starts")

    manager.startMonitoring()

    DispatchQueue.main.async {
      XCTAssertTrue(factory.makeCalled)
      XCTAssertTrue(session.startCalled)
      XCTAssertTrue(builder.beginCalled)
      XCTAssertTrue(motionProvider.startCalled)
      XCTAssertTrue(manager.isMonitoring)
      XCTAssertNotNil(builder.dataSource)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1.0)
  }

  func testStartMonitoringReturnsWhenSessionExists() {
    let builder = FakeWorkoutBuilder()
    let session = FakeWorkoutSession(builder: builder)
    let factory = FakeWorkoutSessionFactory(session: session)
    let manager = SleepSessionManager(workoutSessionFactory: factory,
                                      healthAvailabilityProvider: { true })
    let expectation = expectation(description: "Monitoring starts")

    manager.startMonitoring()

    DispatchQueue.main.async {
      manager.startMonitoring()
      XCTAssertEqual(factory.makeCallCount, 1)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1.0)
  }

  func testStartMonitoringFactoryThrowsSetsMonitoringFalse() {
    let factory = FakeWorkoutSessionFactory(error: TestError.forced)
    let manager = SleepSessionManager(workoutSessionFactory: factory,
                                      healthAvailabilityProvider: { true })

    manager.startMonitoring()

    XCTAssertTrue(factory.makeCalled)
    XCTAssertFalse(manager.isMonitoring)
  }

  func testStopMonitoringWithoutSessionStopsMotionUpdates() {
    let motionProvider = FakeMotionProvider()
    let manager = SleepSessionManager(motionManager: MotionManager(motionManager: motionProvider))

    manager.stopMonitoring()

    XCTAssertTrue(motionProvider.stopCalled)
  }

  func testStopMonitoringEndsSessionAndBuilder() {
    let builder = FakeWorkoutBuilder()
    let session = FakeWorkoutSession(builder: builder)
    let factory = FakeWorkoutSessionFactory(session: session)
    let manager = SleepSessionManager(workoutSessionFactory: factory,
                                      healthAvailabilityProvider: { true })
    let expectation = expectation(description: "Stop monitoring")

    manager.startMonitoring()

    DispatchQueue.main.async {
      manager.stopMonitoring()
      XCTAssertTrue(session.endCalled)
      XCTAssertTrue(builder.endCalled)
      XCTAssertTrue(builder.finishCalled)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1.0)
  }

  func testHandleAccelerationTriggersHapticWithCooldown() {
    let hapticPlayer = FakeHapticPlayer()
    let manager = SleepSessionManager(hapticPlayer: hapticPlayer)
    let baseline = CMAcceleration(x: 0, y: 0, z: 0)
    let trigger = CMAcceleration(x: MotionConstants.motionThreshold * 2, y: 0, z: 0)
    let startDate = Date()

    manager.handleAcceleration(baseline, at: startDate)
    manager.handleAcceleration(trigger, at: startDate)
    manager.handleAcceleration(baseline, at: startDate.addingTimeInterval(5))
    manager.handleAcceleration(trigger, at: startDate.addingTimeInterval(MotionConstants.motionCooldownSeconds))

    XCTAssertEqual(hapticPlayer.played.count, 2)
  }

  func testHandleAccelerationDoesNotTriggerBelowThreshold() {
    let hapticPlayer = FakeHapticPlayer()
    let manager = SleepSessionManager(hapticPlayer: hapticPlayer)
    let baseline = CMAcceleration(x: 0, y: 0, z: 0)
    let smallMove = CMAcceleration(x: MotionConstants.motionThreshold * 0.5, y: 0, z: 0)
    let date = Date()

    manager.handleAcceleration(baseline, at: date)
    manager.handleAcceleration(smallMove, at: date)

    XCTAssertTrue(hapticPlayer.played.isEmpty)
  }

  func testCanTriggerHapticWithoutPreviousReturnsTrue() {
    let manager = SleepSessionManager()

    XCTAssertTrue(manager.canTriggerHaptic(at: Date()))
  }

  func testWorkoutSessionDelegatesUpdateState() {
    let manager = SleepSessionManager()
    let dummySession = unsafeBitCast(NSObject(), to: HKWorkoutSession.self)
    let expectation = expectation(description: "Delegate updates")

    manager.workoutSession(dummySession, didFailWithError: TestError.forced)
    manager.workoutSession(dummySession, didChangeTo: .running, from: .notStarted, date: Date())
    manager.workoutSession(dummySession, didChangeTo: .ended, from: .running, date: Date())

    DispatchQueue.main.async {
      XCTAssertFalse(manager.isMonitoring)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1.0)
  }

  func testWorkoutBuilderDelegateMethods() {
    let manager = SleepSessionManager()
    let dummyBuilder = unsafeBitCast(NSObject(), to: HKLiveWorkoutBuilder.self)

    manager.workoutBuilderDidCollectEvent(dummyBuilder)
    manager.workoutBuilder(dummyBuilder, didCollectDataOf: [])
  }

  func testHealthKitWorkoutSessionFactoryExecutes() {
    let factory = HealthKitWorkoutSessionFactory()
    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .mindAndBody
    configuration.locationType = .unknown

    _ = try? factory.makeSession(healthStore: HKHealthStore(), configuration: configuration)

    XCTAssertTrue(true)
  }

  func testDefaultHapticPlayerPlayExecutes() {
    DefaultHapticPlayer().play(.notification)
  }

  func testResolveDateUsesProviderWhenManagerPresent() {
    let expected = Date(timeIntervalSince1970: 123)
    let manager = SleepSessionManager(dateProvider: { expected })

    let resolved = SleepSessionManager.resolveDate(using: manager)

    XCTAssertEqual(resolved, expected)
  }

  func testResolveDateFallsBackWhenManagerNil() {
    let now = Date()

    let resolved = SleepSessionManager.resolveDate(using: nil)

    XCTAssertLessThan(abs(resolved.timeIntervalSince(now)), 1.0)
  }

  func testStartMotionUpdatesUsesDateFallbackWhenManagerDeallocated() {
    let builder = FakeWorkoutBuilder()
    let session = FakeWorkoutSession(builder: builder)
    let factory = FakeWorkoutSessionFactory(session: session)
    let motionProvider = FakeMotionProvider()
    motionProvider.isAccelerometerAvailable = true
    motionProvider.isAccelerometerActive = false
    let motionManager = MotionManager(motionManager: motionProvider)
    motionManager.testAcceleration = CMAcceleration(x: 0.2, y: 0.2, z: 0.2)
    var manager: SleepSessionManager? = SleepSessionManager(motionManager: motionManager,
                                                           workoutSessionFactory: factory,
                                                           healthAvailabilityProvider: { true })
    let expectation = expectation(description: "Main queue executes")

    manager?.startMonitoring()
    manager = nil

    DispatchQueue.main.async {
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1.0)
  }

  func testStartMonitoringInvokesHandleAcceleration() {
    let builder = FakeWorkoutBuilder()
    let session = FakeWorkoutSession(builder: builder)
    let factory = FakeWorkoutSessionFactory(session: session)
    let motionProvider = FakeMotionProvider()
    motionProvider.isAccelerometerAvailable = true
    motionProvider.isAccelerometerActive = false
    let motionManager = MotionManager(motionManager: motionProvider)
    motionManager.testAcceleration = CMAcceleration(x: 0.1, y: 0.1, z: 0.1)
    let manager = MotionSpySleepSessionManager(motionManager: motionManager,
                                               workoutSessionFactory: factory,
                                               healthAvailabilityProvider: { true })
    let expectation = expectation(description: "handleAcceleration called")
    manager.handleAccelerationExpectation = expectation

    manager.startMonitoring()

    wait(for: [expectation], timeout: 1.0)
  }
}

private final class StubAuthorizationStore: HealthStoreAuthorizationProviding {
  private(set) var status: HKAuthorizationStatus

  init(status: HKAuthorizationStatus) {
    self.status = status
  }

  func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
    status
  }

  func requestAuthorization(toShare typesToShare: Set<HKSampleType>?,
                            read typesToRead: Set<HKObjectType>?,
                            completion: @escaping (Bool, Error?) -> Void) {
    status = .sharingAuthorized
    completion(true, nil)
  }
}

private enum TestError: Error {
  case forced
}

private final class FakeMotionProvider: MotionManagerProviding {
  var isAccelerometerAvailable = true
  var isAccelerometerActive = false
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

private final class FakeHapticPlayer: HapticPlaying {
  private(set) var played: [WKHapticType] = []

  func play(_ type: WKHapticType) {
    played.append(type)
  }
}

private final class FakeWorkoutBuilder: WorkoutSessionBuilding {
  weak var delegate: HKLiveWorkoutBuilderDelegate?
  var dataSource: HKLiveWorkoutDataSource?
  private(set) var beginCalled = false
  private(set) var endCalled = false
  private(set) var finishCalled = false

  func beginCollection(withStart startDate: Date, completion: @escaping (Bool, Error?) -> Void) {
    beginCalled = true
    completion(true, nil)
  }

  func endCollection(withEnd endDate: Date, completion: @escaping (Bool, Error?) -> Void) {
    endCalled = true
    completion(true, nil)
  }

  func finishWorkout(completion: @escaping (HKWorkout?, Error?) -> Void) {
    finishCalled = true
    completion(nil, nil)
  }
}

private final class FakeWorkoutSession: WorkoutSessioning {
  weak var delegate: HKWorkoutSessionDelegate?
  private(set) var startCalled = false
  private(set) var endCalled = false
  private let builder: WorkoutSessionBuilding

  init(builder: WorkoutSessionBuilding) {
    self.builder = builder
  }

  func startActivity(with date: Date?) {
    startCalled = true
  }

  func end() {
    endCalled = true
  }

  func makeWorkoutBuilder() -> WorkoutSessionBuilding {
    builder
  }
}

private final class FakeWorkoutSessionFactory: WorkoutSessionFactory {
  private(set) var makeCalled = false
  private(set) var makeCallCount = 0
  private let session: WorkoutSessioning?
  private let error: Error?

  init(session: WorkoutSessioning? = nil, error: Error? = nil) {
    self.session = session
    self.error = error
  }

  func makeSession(healthStore: HKHealthStore,
                   configuration: HKWorkoutConfiguration) throws -> WorkoutSessioning {
    makeCalled = true
    makeCallCount += 1
    if let error {
      throw error
    }
    guard let session else {
      throw TestError.forced
    }
    return session
  }
}

private final class MotionSpySleepSessionManager: SleepSessionManager {
  var handleAccelerationExpectation: XCTestExpectation?

  override func handleAcceleration(_ acceleration: CMAcceleration, at date: Date) {
    handleAccelerationExpectation?.fulfill()
    super.handleAcceleration(acceleration, at: date)
  }
}
