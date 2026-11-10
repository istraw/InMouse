import AppKit
import ApplicationServices
import XCTest
@testable import StrokeMouse

@MainActor
final class GestureRecordingCanvasTests: XCTestCase {
    func testRecordsEachSupportedButtonAndIncludesReleasePosition() throws {
        for (number, expected) in [(1, MouseTriggerButton.right), (2, .middle), (3, .sideBack), (4, .sideForward)] {
            let view = GestureRecordingCanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
            var result: ([CGPoint], MouseTriggerButton)?
            view.onEnd = { result = ($0, $1) }
            let down = try event(number, type: number == 1 ? .rightMouseDown : .otherMouseDown, x: 10)
            let drag = try event(number, type: number == 1 ? .rightMouseDragged : .otherMouseDragged, x: 40)
            let up = try event(number, type: number == 1 ? .rightMouseUp : .otherMouseUp, x: 80)
            if number == 1 {
                view.rightMouseDown(with: down); view.rightMouseDragged(with: drag); view.rightMouseUp(with: up)
            } else {
                view.otherMouseDown(with: down); view.otherMouseDragged(with: drag); view.otherMouseUp(with: up)
            }
            let recording = try XCTUnwrap(result)
            XCTAssertEqual(recording.1, expected)
            XCTAssertEqual(recording.0.count, 3)
            XCTAssertEqual(recording.0.last!.x - recording.0.first!.x, 70, accuracy: 0.1)
        }
    }

    func testLeftButtonCannotRecordOrEndAnotherButtonsStroke() throws {
        let view = GestureRecordingCanvasView()
        var begins = 0
        var ends = 0
        view.onBegin = { _ in begins += 1 }
        view.onEnd = { _, button in ends += 1; XCTAssertEqual(button, .right) }
        view.mouseDown(with: try event(0, type: .leftMouseDown, x: 10))
        view.mouseDragged(with: try event(0, type: .leftMouseDragged, x: 40))
        view.mouseUp(with: try event(0, type: .leftMouseUp, x: 80))
        XCTAssertEqual(begins, 0)
        XCTAssertEqual(ends, 0)
        view.rightMouseDown(with: try event(1, type: .rightMouseDown, x: 10))
        view.mouseUp(with: try event(0, type: .leftMouseUp, x: 20))
        view.otherMouseDown(with: try event(3, type: .otherMouseDown, x: 25))
        view.otherMouseUp(with: try event(3, type: .otherMouseUp, x: 35))
        XCTAssertEqual(begins, 1)
        XCTAssertEqual(ends, 0)
        view.rightMouseUp(with: try event(1, type: .rightMouseUp, x: 80))
        XCTAssertEqual(ends, 1)
    }

    func testRejectsUnsupportedButtonsAndContextMenu() throws {
        XCTAssertNil(MouseTriggerButton(recordingButtonNumber: 0))
        XCTAssertNil(MouseTriggerButton(recordingButtonNumber: 5))
        let view = GestureRecordingCanvasView()
        view.onBegin = { _ in XCTFail("Unsupported button must not record") }
        view.otherMouseDown(with: try event(5, type: .otherMouseDown, x: 10))
        XCTAssertNil(view.menu(for: try event(1, type: .rightMouseDown, x: 10)))
    }

    private func event(_ button: Int, type: CGEventType, x: CGFloat) throws -> NSEvent {
        let raw = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type,
                                      mouseCursorPosition: CGPoint(x: x, y: 100),
                                      mouseButton: CGMouseButton(rawValue: UInt32(button))!))
        return try XCTUnwrap(NSEvent(cgEvent: raw))
    }
}
