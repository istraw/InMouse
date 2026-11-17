import XCTest
@testable import StrokeMouse

final class WindowLayoutTests: XCTestCase {
    func testWindowActionCategoriesContainEveryActionExactlyOnce() {
        let selections = WindowActionGroup.allCases.flatMap(\.selections)
        XCTAssertEqual(Set(selections).count, selections.count)
        XCTAssertEqual(Set(selections), Set(WindowCommand.allCases.map(WindowActionSelection.window)
            + [.customWindow] + ApplicationSwitchCommand.allCases.map(WindowActionSelection.applicationSwitch)))
        for group in WindowActionGroup.allCases {
            XCTAssertTrue(group.selections.allSatisfy { $0.group == group })
        }
        XCTAssertEqual(WindowActionGroup.layouts.selections.count, 10)
        XCTAssertEqual(WindowActionGroup.arrangements.selections.count, 9)
    }

    @MainActor
    func testNativeLayoutsRoundTripThroughStoreAndRequireVersionTen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("gestures.json")
        let commands = WindowCommand.allCases.filter { $0.nativeLayoutIdentifier != nil }
        XCTAssertEqual(commands.count, 17)
        let profiles = commands.map {
            GestureProfile(name: $0.rawValue, pattern: .freePath(PathTemplates.up), action: .window($0))
        }
        let store = ConfigStore(configURL: url)
        store.replaceAll(profiles)
        XCTAssertNil(store.lastFailure)
        XCTAssertEqual(ConfigStore(configURL: url).gestures, profiles)
        let data = try store.exportPackage(ids: Set(profiles.map(\.id)))
        let exported = try JSONDecoder().decode(GestureConfigFile.self, from: data)
        XCTAssertEqual(exported.version, 10)
        XCTAssertTrue(exported.hasSupportedVersion)
        for var profile in profiles {
            XCTAssertFalse(GestureConfigFile(version: 9, gestures: [profile]).hasSupportedVersion)
            profile.secondaryAction = profile.action
            profile.action = .none
            XCTAssertEqual(GestureConfigFile.requiredVersion(for: [profile]), 10)
        }
    }

    func testHalfAndQuarterFallbacksStayInsideUsableScreen() throws {
        let usable = CGRect(x: -1920, y: -1080, width: 1920, height: 1050)
        for command in WindowCommand.allCases {
            guard let layout = command.fallbackLayout else { continue }
            let frame = try layout.frame(in: usable)
            XCTAssertTrue(usable.contains(frame), "\(command)")
            XCTAssertEqual(frame.width * frame.height / (usable.width * usable.height),
                           [.tileLeft, .tileRight, .tileTop, .tileBottom].contains(command) ? 0.5 : 0.25)
        }
    }

    func testPercentagesUseUsableAreaOriginOnSecondaryDisplay() throws {
        let usable = CGRect(x: -1600, y: -800, width: 1600, height: 900)
        XCTAssertEqual(try WindowLayout().frame(in: usable),
                       CGRect(x: -1440, y: -710, width: 1280, height: 720))
        XCTAssertEqual(try WindowLayout(x: 50, y: 0, width: 50, height: 100).frame(in: usable),
                       CGRect(x: -800, y: -800, width: 800, height: 900))
    }

    func testRejectsInvalidAndNonFiniteLayouts() throws {
        for layout in [WindowLayout(x: -1), WindowLayout(width: 0), WindowLayout(height: -10),
                       WindowLayout(x: 50, width: 60), WindowLayout(y: 99),
                       WindowLayout(x: .nan), WindowLayout(width: .infinity)] {
            XCTAssertFalse(layout.isValid)
            XCTAssertThrowsError(try layout.frame(in: CGRect(x: 0, y: 0, width: 100, height: 100)))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(WindowLayout.self,
            from: Data(#"{"x":90,"y":0,"width":80,"height":100}"#.utf8)))
    }

    func testActionsRoundTripWithoutLosingPercentages() throws {
        let actions: [GestureAction] = [.customWindow(.init(x: 12.5, y: 0, width: 75, height: 100))]
            + WindowCommand.allCases.map { .window($0) }
        for action in actions {
            XCTAssertEqual(try JSONDecoder().decode(GestureAction.self,
                from: JSONEncoder().encode(action)), action)
        }
    }

    func testNewActionsRequireVersionEightIncludingSecondaryActions() {
        for action in [GestureAction.customWindow(WindowLayout())]
            + WindowCommand.allCases.filter(\.isExtended).map({ .window($0) }) {
            var profile = GestureProfile(name: "Layout", pattern: .freePath(PathTemplates.up), action: action)
            XCTAssertEqual(GestureConfigFile.requiredVersion(for: [profile]), 8)
            profile.action = .window(.center)
            profile.secondaryAction = action
            XCTAssertEqual(GestureConfigFile.requiredVersion(for: [profile]), 8)
        }
        XCTAssertEqual(GestureConfigFile.requiredVersion(for: [GestureProfile(
            name: "Old", pattern: .freePath(PathTemplates.up), action: .window(.center))]), 2)
    }
}
