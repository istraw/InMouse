import Foundation
import XCTest
@testable import StrokeMouse

final class PersonalMenuBarPreferencesTests: XCTestCase {
    func testUpgradeEnablesDockHidingAndVisibleMonochromeMenuBar() throws {
        let suite = "InMouseMenuBarTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: PreferenceKey.hideDockIcon)
        defaults.set(true, forKey: PreferenceKey.hideMenuBarIcon)
        defaults.set(MenuBarIconStyle.color.rawValue, forKey: PreferenceKey.menuBarIconStyle)
        PersonalMenuBarPreferences.applyIfNeeded(defaults: defaults, bundleIdentifier: "com.istraw.inmouse")
        XCTAssertTrue(defaults.bool(forKey: PreferenceKey.hideDockIcon))
        XCTAssertFalse(defaults.bool(forKey: PreferenceKey.hideMenuBarIcon))
        XCTAssertEqual(defaults.string(forKey: PreferenceKey.menuBarIconStyle), "monochrome")
        // Do not reset user preferences on every subsequent launch.
        defaults.set(false, forKey: PreferenceKey.hideDockIcon)
        defaults.set(true, forKey: PreferenceKey.hideMenuBarIcon)
        PersonalMenuBarPreferences.applyIfNeeded(defaults: defaults, bundleIdentifier: "com.istraw.inmouse")
        XCTAssertFalse(defaults.bool(forKey: PreferenceKey.hideDockIcon))
        XCTAssertTrue(defaults.bool(forKey: PreferenceKey.hideMenuBarIcon))
    }

    func testDoesNotChangeDevelopmentOrUpstreamPreferences() throws {
        let suite = "InMouseMenuBarTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        PersonalMenuBarPreferences.applyIfNeeded(defaults: defaults, bundleIdentifier: "com.strokemouse.app")
        XCTAssertNil(defaults.object(forKey: PreferenceKey.hideDockIcon))
    }
}
