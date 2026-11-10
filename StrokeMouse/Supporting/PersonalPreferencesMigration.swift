import Foundation

/// Import preferences once from the earlier personal development build.
/// The shared gesture JSON stays in Application Support/StrokeMouse.
enum PersonalPreferencesMigration {
    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        destinationDomain: String? = Bundle.main.bundleIdentifier,
        sourceDomain: String = "com.strokemouse.app.dev"
    ) {
        guard destinationDomain == "com.istraw.inmouse" else { return }
        let marker = "inmouse.didImportDevelopmentPreferences"
        guard !defaults.bool(forKey: marker) else { return }
        var destination = defaults.persistentDomain(forName: destinationDomain!) ?? [:]
        let source = defaults.persistentDomain(forName: sourceDomain) ?? [:]
        for (key, value) in source where destination[key] == nil {
            destination[key] = value
        }
        destination[marker] = true
        defaults.setPersistentDomain(destination, forName: destinationDomain!)
    }
}
