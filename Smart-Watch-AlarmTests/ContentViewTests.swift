import XCTest
@testable import Smart_Watch_Alarm

final class ContentViewTests: XCTestCase {
  func testContentViewBodyRendersMonitoringState() {
    let manager = SleepSessionManager()
    manager.setMonitoringForTesting(true)
    _ = ContentView(sessionManager: manager).body
  }

  func testContentViewBodyRendersSessionEndedState() {
    let manager = SleepSessionManager()
    manager.stopSession()
    _ = ContentView(sessionManager: manager).body
  }

  func testHandlePrimaryTappedStopsMonitoringWhenActive() {
    let manager = SpySleepSessionManager()
    manager.setMonitoringForTesting(true)
    let view = ContentView(sessionManager: manager)

    view.handlePrimaryTapped()

    XCTAssertTrue(manager.stopSessionCalled)
  }

  func testHandlePrimaryTappedDoesNotStopWhenInactive() {
    let manager = SpySleepSessionManager()
    let view = ContentView(sessionManager: manager)

    view.handlePrimaryTapped()

    XCTAssertFalse(manager.stopSessionCalled)
  }

  func testHandleStopTappedCallsStopSession() {
    let manager = SpySleepSessionManager()
    let view = ContentView(sessionManager: manager)

    view.handleStopTapped()

    XCTAssertTrue(manager.stopSessionCalled)
  }

  func testHandleMonitoringChangeDoesNotCrash() {
    let manager = SleepSessionManager()
    let view = ContentView(sessionManager: manager)

    view.handleMonitoringChange(true)
    view.handleMonitoringChange(false)
  }

  func testSessionEndedViewBodyBuilds() {
    _ = SessionEndedView().body
  }

  func testBodyContentRendersSessionEndedState() {
    let manager = SleepSessionManager()
    manager.stopSession()

    _ = ContentView(sessionManager: manager).bodyContent(size: 100)
  }

  func testBodyContentRendersActiveState() {
    let manager = SleepSessionManager()
    manager.setMonitoringForTesting(true)

    _ = ContentView(sessionManager: manager).bodyContent(size: 100)
  }

  func testNextTriggerDateUsesSameDayWhenTimeLater() {
    let calendar = Calendar.current
    let now = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 7, minute: 0))!
    let selectedTime = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 8, minute: 30))!
    let view = ContentView(sessionManager: SleepSessionManager())

    let result = view.nextTriggerDate(from: selectedTime, now: now)

    let expected = calendar.date(from: DateComponents(year: 2025,
                                                      month: 1,
                                                      day: 1,
                                                      hour: 8,
                                                      minute: 30,
                                                      second: 0))!
    XCTAssertEqual(result, expected)
  }

  func testNextTriggerDateMovesToNextDayWhenTimeEarlier() {
    let calendar = Calendar.current
    let now = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 9, minute: 0))!
    let selectedTime = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 8, minute: 30))!
    let view = ContentView(sessionManager: SleepSessionManager())

    let result = view.nextTriggerDate(from: selectedTime, now: now)

    let expectedBase = calendar.date(from: DateComponents(year: 2025,
                                                          month: 1,
                                                          day: 1,
                                                          hour: 8,
                                                          minute: 30,
                                                          second: 0))!
    let expected = calendar.date(byAdding: .day, value: 1, to: expectedBase)!
    XCTAssertEqual(result, expected)
  }
}

private final class SpySleepSessionManager: SleepSessionManager {
  private(set) var stopSessionCalled = false

  override func stopSession() {
    stopSessionCalled = true
    super.stopSession()
  }
}
