import AppKit
import ApplicationServices
import OSLog

/// A narrow AX seam keeps the write ordering and result checks testable.
@MainActor
struct WindowFrameAXClient {
    var readFrame: (AXUIElement) throws -> CGRect = { window in
        let origin = try GestureTargetAXAccessor.copyPoint(
            from: window,
            attribute: .init(name: kAXPositionAttribute as CFString, operation: .copyPosition)
        )
        let size = try GestureTargetAXAccessor.copySize(
            from: window,
            attribute: .init(name: kAXSizeAttribute as CFString, operation: .copySize)
        )
        guard origin.x.isFinite, origin.y.isFinite,
              size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else {
            throw GestureTargetError.windowResizeUnavailable
        }
        return CGRect(origin: origin, size: size)
    }
    var isSettable: (AXUIElement, CFString) -> (AXError, Bool) = { window, attribute in
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(window, attribute, &settable)
        return (result, settable.boolValue)
    }
    var setValue: (AXUIElement, CFString, AXValue) -> AXError = {
        AXUIElementSetAttributeValue($0, $1, $2)
    }

    func requireWritable(_ window: AXUIElement, attribute: CFString) throws {
        let (result, writable) = isSettable(window, attribute)
        if result == .attributeUnsupported || (result == .success && !writable) {
            throw GestureTargetError.windowResizeUnavailable
        }
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(
                operation: attribute as String == kAXPositionAttribute as String
                    ? .checkPositionWritable : .checkSizeWritable,
                code: result
            )
        }
    }

    func write(_ window: AXUIElement, attribute: CFString, value: AXValue) throws {
        let result = setValue(window, attribute, value)
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(
                operation: attribute as String == kAXPositionAttribute as String
                    ? .setPosition : .setSize,
                code: result
            )
        }
    }
}

@MainActor
struct WindowMaximizer {
    var ax = WindowFrameAXClient()
    var completionTimeout: Duration = .milliseconds(500)
    var pollInterval: Duration = .milliseconds(25)
    var frameStabilityInterval: Duration = .milliseconds(150)

    var nativeCommand: (AXUIElement, String) -> Bool = WindowNativeFrameCommands.perform
    var beginImmediateChange: (AXUIElement) -> (() -> Void) = WindowNativeFrameCommands.beginImmediateChange

    @discardableResult
    func maximize(_ window: AXUIElement, to frame: CGRect) async throws -> Bool {
        if Self.framesMatch(try ax.readFrame(window), frame) { return false }
        if nativeCommand(window, "_zoomFill:") {
            // Fill owns its animation and its menu-bar/Dock/margin geometry.
            // Do not interrupt it with AX position/size writes.
            try await waitForNativeFrame(window)
            return true
        }
        try ax.requireWritable(window, attribute: kAXPositionAttribute as CFString)
        try ax.requireWritable(window, attribute: kAXSizeAttribute as CFString)
        try writeImmediateFrame(window, frame: frame, resize: true)
        try await waitForFrame(window, expected: frame)
        return false
    }

    @discardableResult
    func applySystemLayout(_ window: AXUIElement, command: WindowCommand, to frame: CGRect) async throws -> Bool {
        if let identifier = command.nativeLayoutIdentifier, nativeCommand(window, identifier) {
            try await waitForNativeFrame(window)
            return true
        }
        guard command.fallbackLayout != nil else {
            throw GestureTargetError.windowControlUnavailable(command)
        }
        try await applyLayout(window, to: frame)
        return false
    }

    func restore(_ window: AXUIElement, to frame: CGRect) async throws {
        if nativeCommand(window, "_zoomUntile:") {
            try await waitForNativeFrame(window)
            if Self.framesMatch(try ax.readFrame(window), frame) { return }
        }
        try await applyLayout(window, to: frame)
    }

    private func writeImmediateFrame(_ window: AXUIElement, frame: CGRect, resize: Bool) throws {
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimensions = AXValueCreate(.cgSize, &size) else {
            throw GestureTargetError.unexpectedAXValue(operation: .setPosition)
        }
        let finish = beginImmediateChange(window)
        defer { finish() }
        // A resize can be constrained by the old screen/position. Apply the
        // destination size on both sides of the move, without polling between
        // writes or saving intermediate animation frames as restore points.
        if resize { try ax.write(window, attribute: kAXSizeAttribute as CFString, value: dimensions) }
        try ax.write(window, attribute: kAXPositionAttribute as CFString, value: position)
        if resize { try ax.write(window, attribute: kAXSizeAttribute as CFString, value: dimensions) }
    }

    private func waitForNativeFrame(_ window: AXUIElement) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start.advanced(by: max(completionTimeout, .seconds(2)))
        var last = try ax.readFrame(window)
        var stableSince = clock.now
        while true {
            try Task.checkCancellation()
            let actual = try ax.readFrame(window)
            let now = clock.now
            if actual != last { last = actual; stableSince = now }
            if start.duration(to: now) >= .milliseconds(600),
               stableSince.duration(to: now) >= .milliseconds(150) { return }
            guard now < deadline else { throw GestureTargetError.windowMaximizeFailed }
            try await Task.sleep(for: min(pollInterval, now.duration(to: deadline)))
        }
    }

    /// Layouts accept an application's size constraints, but still verify that
    /// resizing took effect and that the final position was applied. Keep the
    /// maximize path strict: filling the display is a different promise.
    @discardableResult
    func applyLayout(_ window: AXUIElement, to requested: CGRect, knownAcceptedSize: CGSize? = nil) async throws -> CGRect {
        try ax.requireWritable(window, attribute: kAXPositionAttribute as CFString)
        let original = try ax.readFrame(window)
        if Self.framesMatch(original, requested) { return original }
        let needsResize = !sizeMatches(original.size, requested.size)
        if needsResize { try ax.requireWritable(window, attribute: kAXSizeAttribute as CFString) }
        try writeImmediateFrame(window, frame: requested, resize: needsResize)
        let resized = needsResize
            ? try await waitForLayoutSize(window, original: original, requested: requested, knownAcceptedSize: knownAcceptedSize)
            : original
        let accepted = CGRect(origin: requested.origin, size: resized.size)
        do {
            try await waitForFrame(window, expected: accepted)
        } catch GestureTargetError.windowMaximizeFailed {
            let actual = try ax.readFrame(window)
            Self.layoutLogger.error("Window layout verification failed: requested=\(NSStringFromRect(requested), privacy: .public), accepted=\(NSStringFromRect(accepted), privacy: .public), actual=\(NSStringFromRect(actual), privacy: .public)")
            throw WindowLayoutError.frameNotApplied
        }
        return try ax.readFrame(window)
    }

    private static let layoutLogger = Logger(subsystem: "com.strokemouse.app", category: "WindowLayout")

    private func waitForLayoutSize(
        _ window: AXUIElement, original: CGRect, requested: CGRect, knownAcceptedSize: CGSize?
    ) async throws -> CGRect {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: completionTimeout)
        var last = original
        var stableSince = clock.now
        while true {
            let actual = try ax.readFrame(window)
            if sizeMatches(actual.size, requested.size) { return actual }
            if let knownAcceptedSize, sizeMatches(actual.size, knownAcceptedSize) { return actual }
            let now = clock.now
            if !sizeMatches(actual.size, last.size) {
                stableSince = now
                last = actual
            }
            // A constrained resize is successful once its new size settles.
            // An unchanged size must not turn ignored AX writes into success.
            let changed = !sizeMatches(actual.size, original.size)
            if changed && stableSince.duration(to: now) >= .milliseconds(150) { return actual }
            if now >= deadline {
                if changed { return actual }
                Self.layoutLogger.error("Window resize had no effect: requested=\(NSStringFromRect(requested), privacy: .public), actual=\(NSStringFromRect(actual), privacy: .public)")
                throw WindowLayoutError.frameNotApplied
            }
            try await Task.sleep(for: min(pollInterval, now.duration(to: deadline)))
        }
    }

    private func sizeMatches(_ actual: CGSize, _ expected: CGSize) -> Bool {
        abs(actual.width - expected.width) <= 2 && abs(actual.height - expected.height) <= 2
    }

    private func waitForFrame(_ window: AXUIElement, expected: CGRect) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: completionTimeout)
        var matchingSince: ContinuousClock.Instant?
        while true {
            let matches = Self.framesMatch(try ax.readFrame(window), expected)
            let now = clock.now
            if matches {
                if matchingSince == nil { matchingSince = now }
                if let matchingSince, matchingSince.duration(to: now) >= frameStabilityInterval { return }
            } else {
                matchingSince = nil
            }
            guard now < deadline else { throw GestureTargetError.windowMaximizeFailed }
            try await Task.sleep(for: min(pollInterval, now.duration(to: deadline)))
        }
    }

    static func framesMatch(_ actual: CGRect, _ expected: CGRect) -> Bool {
        abs(actual.minX - expected.minX) <= 2
            && abs(actual.minY - expected.minY) <= 2
            && abs(actual.width - expected.width) <= 2
            && abs(actual.height - expected.height) <= 2
    }
}

extension MacGestureTargetSystemClient {
    func maximizeWindow(_ target: GestureTargetContext) async throws {
        let window = try target.requireWindow().element
        try await performFrameChange(window, maximize: true) { frame in
            let screens = NSScreen.screens
            guard let zeroScreen = screens.first else { throw GestureTargetError.noScreens }
            let appKitFrame = GestureTargetScreenGeometry.appKitWindowFrame(
                axOrigin: frame.origin, windowSize: frame.size, zeroScreenFrame: zeroScreen.frame
            )
            guard let index = GestureTargetScreenGeometry.targetScreenIndex(
                for: appKitFrame, screenFrames: screens.map(\.frame)
            ) else { throw GestureTargetError.noScreens }
            return GestureTargetScreenGeometry.maximizedAXFrame(
                visibleFrame: screens[index].visibleFrame, zeroScreenFrame: zeroScreen.frame
            )
        }
    }

    func maximizeWindow(_ window: AXUIElement, to destination: CGRect, using maximizer: WindowMaximizer) async throws {
        try await performFrameChange(window, using: maximizer, maximize: true) { _ in destination }
    }
}

/// Menu identifiers are AppKit selectors, independent of the user's language.
/// Menu commands act on the focused window, so never use them for a different
/// frozen target or activate an application merely to make the command work.
@MainActor
private enum WindowNativeFrameCommands {
    static func perform(_ window: AXUIElement, identifier: String) -> Bool {
        guard #available(macOS 15, *) else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        let app = AXUIElementCreateApplication(pid)
        guard let focused = element(app, kAXFocusedWindowAttribute),
              CFEqual(focused, window),
              let menu = element(app, kAXMenuBarAttribute),
              let item = find(menu, identifier: identifier, depth: 0) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    static func beginImmediateChange(_ window: AXUIElement) -> () -> Void {
        // Respect active assistive technologies. Scope the workaround to the
        // synchronous writes and restore the original value even on failure.
        guard !NSWorkspace.shared.isVoiceOverEnabled, !NSWorkspace.shared.isSwitchControlEnabled else { return {} }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return {} }
        let app = AXUIElementCreateApplication(pid)
        let attribute = "AXEnhancedUserInterface" as CFString
        guard copy(app, "AXEnhancedUserInterface") as? Bool == true,
              AXUIElementSetAttributeValue(app, attribute, kCFBooleanFalse) == .success else { return {} }
        return { AXUIElementSetAttributeValue(app, attribute, kCFBooleanTrue) }
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(parent, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func find(_ element: AXUIElement, identifier: String, depth: Int) -> AXUIElement? {
        if copy(element, "AXIdentifier") as? String == identifier { return element }
        guard depth < 7, let children = copy(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children {
            if let item = find(child, identifier: identifier, depth: depth + 1) { return item }
        }
        return nil
    }
}
