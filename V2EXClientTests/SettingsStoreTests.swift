import XCTest
@testable import V2EXClient

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testAppearanceMapsToColorScheme() {
        let store = SettingsStore()

        store.appearanceMode = .system
        XCTAssertNil(store.colorScheme)

        store.appearanceMode = .dark
        XCTAssertEqual(store.colorScheme, .dark)

        store.appearanceMode = .light
        XCTAssertEqual(store.colorScheme, .light)
    }
}
