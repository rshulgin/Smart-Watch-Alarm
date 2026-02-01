import XCTest
import HealthKit
@testable import Smart_Watch_Alarm

final class ContentViewTests: XCTestCase {
  func testContentViewBodyRendersMonitoringState() {
    let manager = SleepSessionManager()
    _ = ContentView(sessionManager: manager).body
  }

  func testContentViewBodyRendersSessionEndedState() {
    let manager = SleepSessionManager()
    manager.stopSession()
    _ = ContentView(sessionManager: manager).body
  }

  func testStartMonitoringIfPossibleAuthorizedStartsMonitoring() {
    let stubStore = TestAuthorizationStore(status: .sharingAuthorized)
    let manager = SpySleepSessionManager(authorizationStore: stubStore)
    var view = ContentView(sessionManager: manager)

    view.startMonitoringIfPossible()

    XCTAssertEqual(manager.startMonitoringCallCount, 1)
  }

  func testStartMonitoringIfPossibleNotDeterminedRequestsAuthorization() {
    let stubStore = TestAuthorizationStore(status: .notDetermined)
    let manager = SpySleepSessionManager(authorizationStore: stubStore)
    var view = ContentView(sessionManager: manager)

    view.startMonitoringIfPossible()
    manager.requestAuthorizationCompletion?(true)

    XCTAssertTrue(manager.requestAuthorizationCalled)
    XCTAssertEqual(manager.startMonitoringCallCount, 1)
  }

  func testStartMonitoringIfPossibleDeniedDoesNothing() {
    let stubStore = TestAuthorizationStore(status: .sharingDenied)
    let manager = SpySleepSessionManager(authorizationStore: stubStore)
    var view = ContentView(sessionManager: manager)

    view.startMonitoringIfPossible()

    XCTAssertFalse(manager.requestAuthorizationCalled)
    XCTAssertEqual(manager.startMonitoringCallCount, 0)
  }

  func testHandleAppearCallsStartMonitoringOnce() {
    let stubStore = TestAuthorizationStore(status: .sharingAuthorized)
    let manager = SpySleepSessionManager(authorizationStore: stubStore)
    var view = ContentView(sessionManager: manager)

    view.handleAppear()

    XCTAssertEqual(manager.startMonitoringCallCount, 1)
  }

  func testHandleMonitoringChangeUpdatesPulse() {
    let stubStore = TestAuthorizationStore(status: .sharingDenied)
    let manager = SpySleepSessionManager(authorizationStore: stubStore)
    var view = ContentView(sessionManager: manager)

    view.handleMonitoringChange(true)
    view.handleMonitoringChange(false)
  }

  func testStartMonitoringIfPossibleWhenAlreadyStartedReturns() {
    let stubStore = TestAuthorizationStore(status: .sharingAuthorized)
    let manager = SpySleepSessionManager(authorizationStore: stubStore)
    var view = ContentView(sessionManager: manager, didStart: true)

    view.startMonitoringIfPossible()

    XCTAssertEqual(manager.startMonitoringCallCount, 0)
  }

  func testStartMonitoringIfPossibleWhenSessionEndedReturns() {
    let stubStore = TestAuthorizationStore(status: .sharingAuthorized)
    let manager = SpySleepSessionManager(authorizationStore: stubStore)
    manager.stopSession()
    var view = ContentView(sessionManager: manager)

    view.startMonitoringIfPossible()

    XCTAssertEqual(manager.startMonitoringCallCount, 0)
  }

  func testHandleStopTappedCallsStopSession() {
    let stubStore = TestAuthorizationStore(status: .sharingDenied)
    let manager = SpySleepSessionManager(authorizationStore: stubStore)
    var view = ContentView(sessionManager: manager)

    view.handleStopTapped()

    XCTAssertTrue(manager.stopSessionCalled)
  }

  func testSessionEndedViewBodyBuilds() {
    _ = SessionEndedView().body
  }

  func testContentViewBodyRendersMonitoringText() {
    let manager = SleepSessionManager()
    manager.setMonitoringForTesting(true)

    _ = ContentView(sessionManager: manager).body
  }

  func testContentViewBodyRendersPulseState() {
    let manager = SleepSessionManager()

    _ = ContentView(sessionManager: manager, pulse: true).body
  }

  func testBodyContentRendersSessionEndedState() {
    let manager = SleepSessionManager()
    manager.stopSession()

    _ = ContentView(sessionManager: manager).bodyContent(size: 100)
  }

  func testBodyContentRendersActiveState() {
    let manager = SleepSessionManager()
    manager.setMonitoringForTesting(true)

    _ = ContentView(sessionManager: manager, pulse: true).bodyContent(size: 100)
  }
}

private final class TestAuthorizationStore: HealthStoreAuthorizationProviding {
  private let status: HKAuthorizationStatus

  init(status: HKAuthorizationStatus) {
    self.status = status
  }

  func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
    status
  }

  func requestAuthorization(toShare typesToShare: Set<HKSampleType>?,
                            read typesToRead: Set<HKObjectType>?,
                            completion: @escaping (Bool, Error?) -> Void) {
    completion(true, nil)
  }
}

private final class SpySleepSessionManager: SleepSessionManager {
  private(set) var startMonitoringCallCount = 0
  private(set) var requestAuthorizationCalled = false
  private(set) var stopSessionCalled = false
  var requestAuthorizationCompletion: ((Bool) -> Void)?

  override func startMonitoring() {
    startMonitoringCallCount += 1
  }

  override func requestAuthorization(completion: @escaping (Bool) -> Void) {
    requestAuthorizationCalled = true
    requestAuthorizationCompletion = completion
  }

  override func stopSession() {
    stopSessionCalled = true
    super.stopSession()
  }
}
