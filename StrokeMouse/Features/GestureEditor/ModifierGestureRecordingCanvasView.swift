import AppKit
import SwiftUI

struct ModifierButtonDrawCatcher: NSViewRepresentable {
    let modifier: GestureModifierKey
    @Binding var isDrawing: Bool
    @Binding var draft: [CGPoint]
    var onFinished: ([CGPoint]) -> Void

    func makeNSView(context: Context) -> ModifierGestureRecordingCanvasView {
        let view = ModifierGestureRecordingCanvasView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ModifierGestureRecordingCanvasView, context: Context) {
        view.modifier = modifier
        view.onBegin = { isDrawing = true; draft = [$0] }
        view.onMove = { draft.append($0) }
        view.onEnd = { isDrawing = false; onFinished($0) }
        view.onCancel = { isDrawing = false; draft = [] }
    }

    static func dismantleNSView(_ view: ModifierGestureRecordingCanvasView, coordinator: ()) {
        view.stopMonitoring()
    }
}

/// Passive, app-local flags observer plus pointer sampling. No clicks, touch API,
/// mouse movement event tap, or Accessibility permission are needed to record.
final class ModifierGestureRecordingCanvasView: NSView {
    var modifier: GestureModifierKey = .function {
        didSet {
            guard modifier != oldValue else { return }
            cancelStroke()
            machine = ModifierFlagsStateMachine(watchedKeys: [modifier])
        }
    }
    var onBegin: ((CGPoint) -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onEnd: (([CGPoint]) -> Void)?
    var onCancel: (() -> Void)?
    private var machine = ModifierFlagsStateMachine(watchedKeys: [.function])
    private var points: [CGPoint] = []
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func menu(for event: NSEvent) -> NSMenu? { nil }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard let window else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.receiveCurrentPointer(flags: event.modifierFlags)
            return event // Never swallow modifier keys or the system's Fn behavior.
        }
        for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject),
                               (NSApplication.didResignActiveNotification, NSApp as AnyObject)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupt() }
            })
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        timer?.invalidate()
        timer = nil
        cancelStroke()
        machine.reset()
    }

    private func interrupt() {
        _ = machine.interrupt(keys: ModifierEventTap.supportedKeys(in: CGEventFlags(rawValue: UInt64(NSEvent.modifierFlags.rawValue))))
        cancelStroke()
    }

    private func receiveCurrentPointer(flags: NSEvent.ModifierFlags) {
        guard let window else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        receive(keys: ModifierEventTap.supportedKeys(in: CGEventFlags(rawValue: UInt64(flags.rawValue))),
                point: point, eligible: window.isKeyWindow && NSApp.isActive)
    }

    /// Shared by event boundaries and timer samples; also testable without global input.
    func receive(keys: Set<GestureModifierKey>, point: CGPoint, eligible: Bool = true) {
        guard eligible, bounds.contains(point) else {
            _ = machine.interrupt(keys: keys)
            cancelStroke()
            return
        }
        switch machine.process(keys: keys) {
        case .began:
            points = [point]
            onBegin?(point)
            startSampling()
        case .ended:
            guard !points.isEmpty else { return }
            append(point)
            let finished = points
            points = []
            timer?.invalidate()
            timer = nil
            onEnd?(finished)
        case .cancelled, .interrupted:
            cancelStroke()
        case .drained:
            break
        case nil:
            if !points.isEmpty { append(point) }
        }
    }

    private func append(_ point: CGPoint) {
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 1 { return }
        points.append(point)
        onMove?(point)
    }

    private func startSampling() {
        timer?.invalidate()
        guard window != nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.receiveCurrentPointer(flags: NSEvent.modifierFlags) }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelStroke() {
        timer?.invalidate()
        timer = nil
        let wasDrawing = !points.isEmpty
        points = []
        if wasDrawing { onCancel?() }
    }

    deinit {
        timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
