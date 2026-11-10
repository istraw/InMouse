import Foundation
import XCTest
@testable import StrokeMouse

final class PersonalPreferencesMigrationTests: XCTestCase {
    func testImportsDevelopmentPreferencesWithoutReplacingReleaseValues() {
        let defaults = MigrationDefaults()
        defaults.domains["com.strokemouse.app.dev"] = ["language": "zh-Hans", "showMatchToast": false]
        defaults.domains["com.istraw.inmouse"] = ["language": "en"]
        PersonalPreferencesMigration.runIfNeeded(defaults: defaults, destinationDomain: "com.istraw.inmouse")
        let result = defaults.domains["com.istraw.inmouse"]!
        XCTAssertEqual(result["language"] as? String, "en")
        XCTAssertEqual(result["showMatchToast"] as? Bool, false)
        XCTAssertEqual(result["inmouse.didImportDevelopmentPreferences"] as? Bool, true)
    }

    func testDoesNotMigrateIntoDevelopmentOrUpstreamDomains() {
        let defaults = MigrationDefaults()
        defaults.domains["com.strokemouse.app.dev"] = ["language": "zh-Hans"]
        PersonalPreferencesMigration.runIfNeeded(defaults: defaults, destinationDomain: "com.strokemouse.app")
        XCTAssertNil(defaults.domains["com.strokemouse.app"])
    }

    func testMigrationRunsOnlyOnce() {
        let defaults = MigrationDefaults()
        defaults.domains["com.strokemouse.app.dev"] = ["language": "zh-Hans"]
        PersonalPreferencesMigration.runIfNeeded(defaults: defaults, destinationDomain: "com.istraw.inmouse")
        defaults.domains["com.strokemouse.app.dev"] = ["language": "fr", "newKey": "value"]
        PersonalPreferencesMigration.runIfNeeded(defaults: defaults, destinationDomain: "com.istraw.inmouse")
        XCTAssertNil(defaults.domains["com.istraw.inmouse"]?["newKey"])
    }
}

private final class MigrationDefaults: UserDefaults, @unchecked Sendable {
    var domains: [String: [String: Any]] = [:]
    override func persistentDomain(forName domainName: String) -> [String: Any]? { domains[domainName] }
    override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) { domains[domainName] = domain }
    override func bool(forKey defaultName: String) -> Bool {
        domains["com.istraw.inmouse"]?[defaultName] as? Bool ?? false
    }
}
