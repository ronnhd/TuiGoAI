@testable import TuiGoAI
import XCTest

// MARK: - Update Manager Tests

final class UpdateManagerTests: XCTestCase {
    func testSharedInstanceExists() {
        XCTAssertNotNil(UpdateManager.shared)
    }

    func testDefaultUpdateAvailableIsFalse() {
        XCTAssertFalse(UpdateManager.shared.updateAvailable)
    }

    func testVersionCompareFFI() {
        "0.1.0-alpha.1".withCString { cur in
            "0.1.0-alpha.2".withCString { next in
                XCTAssertEqual(version_has_update(cur, next), 1)
                XCTAssertEqual(version_compare(cur, next), -1)
            }
        }

        "0.1.0-alpha".withCString { alpha in
            "0.1.0-beta".withCString { beta in
                XCTAssertEqual(version_has_update(alpha, beta), 1)
            }
        }

        "0.1.0-beta".withCString { beta in
            "0.1.0".withCString { official in
                XCTAssertEqual(version_has_update(beta, official), 1)
            }
        }
    }
}
