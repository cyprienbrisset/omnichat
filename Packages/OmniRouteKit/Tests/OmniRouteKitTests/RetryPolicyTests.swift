import XCTest
@testable import OmniRouteKit

final class RetryPolicyTests: XCTestCase {
    func test_delay_growsExponentiallyAndCaps() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1.0, maxDelay: 4.0)
        XCTAssertEqual(policy.delay(forAttempt: 1, jitter: 0), 1.0)
        XCTAssertEqual(policy.delay(forAttempt: 2, jitter: 0), 2.0)
        XCTAssertEqual(policy.delay(forAttempt: 3, jitter: 0), 4.0)
        XCTAssertEqual(policy.delay(forAttempt: 4, jitter: 0), 4.0, "must cap at maxDelay")
    }

    func test_shouldRetry_trueForTransientErrorsUnderMaxAttempts() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.1, maxDelay: 1.0)
        XCTAssertTrue(policy.shouldRetry(attempt: 1, error: .network(description: "timeout")))
        XCTAssertFalse(policy.shouldRetry(attempt: 3, error: .network(description: "timeout")), "must stop at maxAttempts")
    }

    func test_shouldRetry_falseForAuthenticationFailed() {
        let policy = RetryPolicy()
        XCTAssertFalse(policy.shouldRetry(attempt: 1, error: .authenticationFailed))
    }
}
