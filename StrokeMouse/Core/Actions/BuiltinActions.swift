import AppKit
import Carbon.HIToolbox
import Foundation
import IOKit.pwr_mgt
import UniformTypeIdentifiers

enum BuiltinActionError: String, LocalizedError {
    case unsupportedBrowser, unavailable, noWallpaperImages, selectImage, cancelled
    var errorDescription: String? { L10n.string("builtin.error.\(rawValue)") }
}

@MainActor
final class KeepAwakeController {
    private(set) var assertionID: IOPMAssertionID?
    private let create: () -> (IOReturn, IOPMAssertionID)
    private let release: (IOPMAssertionID) -> IOReturn

    init(
        create: @escaping () -> (IOReturn, IOPMAssertionID) = {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "InMouse keep awake" as CFString, &id
            )
            return (result, id)
        },
        release: @escaping (IOPMAssertionID) -> IOReturn = { IOPMAssertionRelease($0) }
    ) {
        self.create = create
        self.release = release
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard assertionID == nil else { return }
            let (result, id) = create()
            guard result == kIOReturnSuccess else { throw BuiltinActionError.unavailable }
            assertionID = id
        } else if let id = assertionID {
            guard release(id) == kIOReturnSuccess else { throw BuiltinActionError.unavailable }
            assertionID = nil
        }
    }

    deinit {
        if let assertionID { _ = release(assertionID) }
    }
}

@MainActor
final class BuiltinActions {
    static let shared = BuiltinActions()
    private let keepAwake = KeepAwakeController()

    func perform(_ action: BuiltinAction) async throws {
        let command = action.command
        if command.requiresConfirmation {
            let alert = NSAlert()
            alert.messageText = L10n.string(command.displayKey)
            alert.informativeText = L10n.string("builtin.confirmation")
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.string("common.continue"))
            alert.addButton(withTitle: L10n.string("common.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { throw BuiltinActionError.cancelled }
        }
        if let script = Self.script(for: command) {
            try await ScriptActions.runAppleScript(script)
            return
        }
        if let chord = Self.finderChord(for: command) {
            try await ScriptActions.runAppleScript(Self.finderShortcutScript(chord))
            return
        }
        switch command {
        case .showDesktop:
            // Respect the user's system binding; an explicitly disabled shortcut is an error.
            CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
            let hotKeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                "com.apple.symbolichotkeys" as CFString) as? [String: Any]
            let chord: ShortcutChord
            switch SystemCommand.shortcutStatus(from: hotKeys?["36"]) {
            case .disabled: throw BuiltinActionError.unavailable
            case .enabled(let configured): chord = configured
            case .unknown: chord = ShortcutChord(modifiers: [], keyCode: UInt16(kVK_F11))
            }
            try Self.post(chord)
        case .toggleDock:
            try Self.post(ShortcutChord(modifiers: [.option, .command], keyCode: UInt16(kVK_ANSI_D)))
        case .stayAwake: try keepAwake.setEnabled(true)
        case .allowSleep: try keepAwake.setEnabled(false)
        case .randomWallpaper:
            guard let directory = action.wallpaperDirectory else { throw BuiltinActionError.noWallpaperImages }
            let images = try Self.wallpaperImages(in: URL(fileURLWithPath: directory, isDirectory: true))
            let current = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }?.standardizedFileURL
            let candidates = images.count > 1 ? images.filter { $0.standardizedFileURL != current } : images
            guard let image = candidates.randomElement() else { throw BuiltinActionError.noWallpaperImages }
            try Self.setWallpaper(image)
        case .finderSelectionAsWallpaper:
            let path = try await ScriptActions.appleScriptString("""
            tell application "Finder"
                if (count of selection) is not 1 then return ""
                return POSIX path of ((item 1 of (get selection)) as alias)
            end tell
            """)
            guard !path.isEmpty else { throw BuiltinActionError.selectImage }
            try Self.setWallpaper(URL(fileURLWithPath: path))
        default:
            guard let url = Self.finderURL(for: command),
                  FileManager.default.fileExists(atPath: url.path),
                  NSWorkspace.shared.open(url) else { throw BuiltinActionError.unavailable }
        }
    }

    static func post(_ chord: ShortcutChord) throws {
        try ShortcutAction.post(keyCode: chord.legacyKeyCode,
                                modifiers: chord.legacyModifiers, orderedChord: chord)
    }

    static func finderURL(for command: BuiltinCommand) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch command {
        case .finderRoot: return URL(fileURLWithPath: "/", isDirectory: true)
        case .finderHome: return home
        case .finderDownloads: return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .finderApplications: return URL(fileURLWithPath: "/Applications", isDirectory: true)
        case .finderDocuments: return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        case .finderICloud: return home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        default: return nil
        }
    }

    static func finderChord(for command: BuiltinCommand) -> ShortcutChord? {
        let key: Int
        let modifiers: [ShortcutModifier]
        switch command {
        case .finderNewWindow: key = kVK_ANSI_N; modifiers = [.command]
        case .finderNewFolder: key = kVK_ANSI_N; modifiers = [.command, .shift]
        case .finderParent: key = kVK_UpArrow; modifiers = [.command]
        case .finderOpenSelection: key = kVK_DownArrow; modifiers = [.command]
        case .finderAirDrop: key = kVK_ANSI_R; modifiers = [.command, .shift]
        case .finderRecents: key = kVK_ANSI_F; modifiers = [.command, .shift]
        case .finderNetwork: key = kVK_ANSI_K; modifiers = [.command, .shift]
        case .finderGoToFolder: key = kVK_ANSI_G; modifiers = [.command, .shift]
        case .finderConnectToServer: key = kVK_ANSI_K; modifiers = [.command]
        default: return nil
        }
        return ShortcutChord(modifiers: modifiers, keyCode: UInt16(key))
    }

    static func finderShortcutScript(_ chord: ShortcutChord) -> String {
        let modifiers = chord.modifiers.map { "\($0.rawValue) down" }.joined(separator: ", ")
        return """
        tell application "Finder" to activate
        tell application "System Events"
            tell process "Finder"
                set frontmost to true
                key code \(chord.legacyKeyCode) using {\(modifiers)}
            end tell
        end tell
        """
    }

    static func script(for command: BuiltinCommand) -> String? {
        switch command {
        case .shutDown: return AppleScriptPreset.shutDown.source
        case .restart: return AppleScriptPreset.restart.source
        case .sleep: return AppleScriptPreset.sleep.source
        case .lockScreen: return AppleScriptPreset.lockScreen.source
        case .startScreenSaver: return AppleScriptPreset.startScreenSaver.source
        case .emptyTrash: return AppleScriptPreset.emptyTrash.source
        case .darkMode, .lightMode:
            return "tell application \"System Events\" to tell appearance preferences to set dark mode to \(command == .darkMode ? "true" : "false")"
        case .showDesktopFiles, .hideDesktopFiles:
            // Finder caches CreateDesktop. Preserve folder windows when restarting it.
            let value = command == .showDesktopFiles ? "true" : "false"
            return """
            tell application "Finder"
                set savedWindows to {}
                repeat with w in Finder windows
                    try
                        set end of savedWindows to {target of w as alias, bounds of w}
                    end try
                end repeat
            end tell
            do shell script "/usr/bin/defaults write com.apple.finder CreateDesktop -bool \(value)"
            tell application "Finder" to quit
            delay 0.5
            tell application "Finder"
                launch
                repeat with savedWindow in savedWindows
                    try
                        set w to make new Finder window to (item 1 of savedWindow)
                        set bounds of w to (item 2 of savedWindow)
                    end try
                end repeat
            end tell
            """
        default: return nil
        }
    }

    static func wallpaperImages(in directory: URL) throws -> [URL] {
        // Only direct children, so a gesture cannot accidentally traverse a huge directory tree.
        try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
            options: [.skipsHiddenFiles]).filter { url in
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
                      values.isRegularFile == true else { return false }
                return values.contentType?.conforms(to: .image) == true
            }
    }

    private static func setWallpaper(_ url: URL) throws {
        guard NSImage(contentsOf: url) != nil else { throw BuiltinActionError.selectImage }
        guard !NSScreen.screens.isEmpty else { throw BuiltinActionError.unavailable }
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }
}
