import Foundation

/// Adopt the requested menu-bar-only idle behavior once when upgrading to 0.1.1.
/// Subsequent changes in General settings remain the user's choice.
enum PersonalMenuBarPreferences {
    static func applyIfNeeded(
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        guard bundleIdentifier == "com.istraw.inmouse" else { return }
        let marker = "inmouse.didAdoptMenuBarMode.v1"
        guard !defaults.bool(forKey: marker) else { return }
        defaults.set(true, forKey: PreferenceKey.hideDockIcon)
        defaults.set(false, forKey: PreferenceKey.hideMenuBarIcon)
        defaults.set(MenuBarIconStyle.monochrome.rawValue, forKey: PreferenceKey.menuBarIconStyle)
        defaults.set(true, forKey: marker)
    }
}
