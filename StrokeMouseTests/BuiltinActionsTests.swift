import AppKit
import IOKit.pwr_mgt
import SwiftUI
import XCTest
@testable import StrokeMouse

@MainActor
final class BuiltinActionsTests: XCTestCase {
    func testBuiltinActionsSurviveExportImportAndReloadWithoutChangingLegacyVersions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = BuiltinCommand.allCases.map { command in
            GestureProfile(name: command.rawValue, pattern: .freePath(PathTemplates.up),
                action: BuiltinAction(command: command,
                    wallpaperDirectory: command == .randomWallpaper ? "/tmp/Wallpapers" : nil).gestureAction)
        }
        let url = directory.appendingPathComponent("gestures.json")
        let store = ConfigStore(configURL: url)
        store.replaceAll(profiles)
        XCTAssertNil(store.lastFailure)
        let data = try store.exportPackage(ids: Set(profiles.map(\.id)))
        let file = try JSONDecoder().decode(GestureConfigFile.self, from: data)
        XCTAssertEqual(file.version, 9)
        XCTAssertEqual(file.gestures, profiles)
        XCTAssertEqual(ConfigStore(configURL: url).gestures, profiles)
        let importing = ConfigStore(configURL: directory.appendingPathComponent("import.json"))
        importing.replaceAll([])
        _ = try importing.importPackage(from: data)
        XCTAssertEqual(importing.gestures.map(\.action), profiles.map(\.action))
        for command in SystemCommand.allCases {
            let legacy = GestureProfile(name: "Legacy", pattern: .freePath(PathTemplates.up),
                                        action: .system(SystemAction(command: command)))
            XCTAssertEqual(GestureConfigFile.requiredVersion(for: [legacy]), 4)
            XCTAssertEqual(BuiltinAction(command: .from(command)).gestureAction, legacy.action)
        }
        var secondary = GestureProfile(name: "Secondary", pattern: .freePath(PathTemplates.up), action: .none)
        secondary.secondaryAction = .builtin(BuiltinAction(command: .stayAwake))
        XCTAssertEqual(GestureConfigFile.requiredVersion(for: [secondary]), 9)
        XCTAssertFalse(GestureConfigFile(version: 8, gestures: [secondary]).hasSupportedVersion)
    }

    func testScriptsCompileWithoutExecutingAnySystemChanges() throws {
        for command in BuiltinCommand.allCases {
            let source = BuiltinActions.script(for: command)
                ?? BuiltinActions.finderChord(for: command).map(BuiltinActions.finderShortcutScript)
            guard let source else { continue }
            let script = try XCTUnwrap(NSAppleScript(source: source))
            var error: NSDictionary?
            XCTAssertTrue(script.compileAndReturnError(&error), "\(command): \(String(describing: error))")
        }
    }

    func testKeepAwakeIsIdempotentAndOnlyReleasesItsOwnAssertion() throws {
        var creates = 0
        var released: [IOPMAssertionID] = []
        let controller = KeepAwakeController(create: { creates += 1; return (kIOReturnSuccess, 73) },
                                            release: { released.append($0); return kIOReturnSuccess })
        try controller.setEnabled(false)
        try controller.setEnabled(true)
        try controller.setEnabled(true)
        XCTAssertEqual(creates, 1)
        XCTAssertEqual(controller.assertionID, 73)
        try controller.setEnabled(false)
        try controller.setEnabled(false)
        XCTAssertEqual(released, [73])
        XCTAssertNil(controller.assertionID)
    }

    func testKeepAwakeFailuresRemainObservableAndRetryable() throws {
        var releaseResult = kIOReturnError
        let failed = KeepAwakeController(create: { (kIOReturnError, 0) })
        XCTAssertThrowsError(try failed.setEnabled(true))
        XCTAssertNil(failed.assertionID)
        let controller = KeepAwakeController(create: { (kIOReturnSuccess, 91) }, release: { _ in releaseResult })
        try controller.setEnabled(true)
        XCTAssertThrowsError(try controller.setEnabled(false))
        XCTAssertEqual(controller.assertionID, 91)
        releaseResult = kIOReturnSuccess
        try controller.setEnabled(false)
        XCTAssertNil(controller.assertionID)
    }

    func testWallpaperScanDoesNotTraverseFoldersOrIncludeHiddenFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j5X8AAAAASUVORK5CYII="))
        try data.write(to: directory.appendingPathComponent("wallpaper.png"))
        try data.write(to: directory.appendingPathComponent(".hidden.png"))
        try Data("text".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("nested.png"), withIntermediateDirectories: true)
        XCTAssertEqual(try BuiltinActions.wallpaperImages(in: directory).map(\.lastPathComponent), ["wallpaper.png"])
    }

    func testEveryCommandHasAnExecutionRouteAndLocalizedTitle() {
        for command in BuiltinCommand.allCases {
            let hasRoute = command.legacySystemCommand != nil || command.browserChord != nil
                || BuiltinActions.script(for: command) != nil || BuiltinActions.finderChord(for: command) != nil
                || BuiltinActions.finderURL(for: command) != nil
                || [.showDesktop, .toggleDock, .stayAwake, .allowSleep, .randomWallpaper, .finderSelectionAsWallpaper].contains(command)
            XCTAssertTrue(hasRoute, command.rawValue)
            XCTAssertNotEqual(L10n.string(command.displayKey), command.displayKey)
        }
    }

    func testRenderActionCategories() throws {
        guard ProcessInfo.processInfo.environment["INMOUSE_RENDER_BUILTINS"] == "1" else { throw XCTSkip("Optional UI snapshots") }
        L10n.apply(.simplifiedChinese)
        defer { L10n.apply(.system) }
        let fixtures: [(GestureEditorView.ActionKind, GestureAction)] = [
            (.desktop, .system(SystemAction(command: .missionControl))),
            (.browser, .builtin(BuiltinAction(command: .browserBack))),
            (.system, .builtin(BuiltinAction(command: .sleep))),
            (.finder, .builtin(BuiltinAction(command: .finderNewWindow))),
        ]
        for (kind, action) in fixtures {
            let view = NSHostingView(rootView: Form {
                ActionPickerView(kind: .constant(kind), action: .constant(action))
            }.formStyle(.grouped).frame(width: 600, height: 350))
            view.frame = NSRect(x: 0, y: 0, width: 600, height: 350)
            view.appearance = NSAppearance(named: .darkAqua)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/inmouse-actions-\(kind.rawValue).png"))
        }
    }
}
