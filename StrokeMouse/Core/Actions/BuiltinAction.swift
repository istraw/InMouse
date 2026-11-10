import Carbon.HIToolbox
import Foundation

enum BuiltinActionGroup: String, CaseIterable, Sendable {
    case desktop, browser, system, finder
    var titleKey: String { "action.\(rawValue)" }
    var commands: [BuiltinCommand] { BuiltinCommand.allCases.filter { $0.group == self } }
}

enum BuiltinCommand: String, Codable, CaseIterable, Identifiable, Sendable {
    case missionControl, applicationWindows, spaceLeft, spaceRight
    case showDesktop, toggleDock, showDesktopFiles, hideDesktopFiles
    case browserBack, browserForward, browserTop, browserBottom
    case browserNewTab, browserCloseTab, browserPreviousTab, browserNextTab
    case shutDown, restart, sleep, lockScreen, startScreenSaver
    case darkMode, lightMode, emptyTrash, stayAwake, allowSleep, randomWallpaper
    case finderNewWindow, finderNewFolder, finderParent, finderOpenSelection
    case finderAirDrop, finderRoot, finderDownloads, finderApplications, finderRecents
    case finderHome, finderDocuments, finderICloud, finderNetwork
    case finderGoToFolder, finderConnectToServer, finderSelectionAsWallpaper

    var id: String { rawValue }
    var displayKey: String { "builtin.\(rawValue)" }
    var group: BuiltinActionGroup {
        switch self {
        case .missionControl, .applicationWindows, .spaceLeft, .spaceRight,
             .showDesktop, .toggleDock, .showDesktopFiles, .hideDesktopFiles: return .desktop
        case .browserBack, .browserForward, .browserTop, .browserBottom,
             .browserNewTab, .browserCloseTab, .browserPreviousTab, .browserNextTab: return .browser
        case .shutDown, .restart, .sleep, .lockScreen, .startScreenSaver,
             .darkMode, .lightMode, .emptyTrash, .stayAwake, .allowSleep, .randomWallpaper: return .system
        default: return .finder
        }
    }
    var legacySystemCommand: SystemCommand? {
        switch self {
        case .missionControl: return .missionControl
        case .applicationWindows: return .applicationWindows
        case .spaceLeft: return .spaceLeft
        case .spaceRight: return .spaceRight
        default: return nil
        }
    }
    static func from(_ command: SystemCommand) -> Self {
        // These names intentionally match the persisted, existing system commands.
        Self(rawValue: command.rawValue)!
    }
    var browserChord: ShortcutChord? {
        let key: Int
        let modifiers: [ShortcutModifier]
        switch self {
        case .browserBack: key = kVK_ANSI_LeftBracket; modifiers = [.command]
        case .browserForward: key = kVK_ANSI_RightBracket; modifiers = [.command]
        case .browserTop: key = kVK_UpArrow; modifiers = [.command]
        case .browserBottom: key = kVK_DownArrow; modifiers = [.command]
        case .browserNewTab: key = kVK_ANSI_T; modifiers = [.command]
        case .browserCloseTab: key = kVK_ANSI_W; modifiers = [.command]
        case .browserPreviousTab: key = kVK_Tab; modifiers = [.control, .shift]
        case .browserNextTab: key = kVK_Tab; modifiers = [.control]
        default: return nil
        }
        return ShortcutChord(modifiers: modifiers, keyCode: UInt16(key))
    }
    var requiresConfirmation: Bool { [.shutDown, .restart, .emptyTrash].contains(self) }
}

struct BuiltinAction: Codable, Equatable, Sendable {
    var command: BuiltinCommand
    /// User-selected directory; no arbitrary shell or script source is persisted.
    var wallpaperDirectory: String?

    init(command: BuiltinCommand, wallpaperDirectory: String? = nil) {
        self.command = command
        self.wallpaperDirectory = wallpaperDirectory
    }

    var gestureAction: GestureAction {
        if let command = command.legacySystemCommand {
            return .system(SystemAction(command: command))
        }
        return .builtin(self)
    }

    static let supportedBrowsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome",
        "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.microsoft.edgemac", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.brave.Browser", "com.brave.Browser.beta", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.kagi.kagimacOS", "app.zen-browser.zen",
    ]
}
