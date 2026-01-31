import XCTest
import HealthKit
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
