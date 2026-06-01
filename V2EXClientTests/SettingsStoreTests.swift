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

    func testContentFontScaleCalculatesScaledSize() {
        let store = SettingsStore()

        store.fontScale = 1.2

        XCTAssertEqual(store.scaledContentSize(10), 12, accuracy: 0.001)
    }
}
