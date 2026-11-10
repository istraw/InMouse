import AppKit
import SwiftUI

struct GestureRecorderView: View {
    @Binding var path: [CodablePoint]
    var onRecordedButton: ((MouseTriggerButton) -> Void)?
    var onRecordedPath: (([CGPoint]) -> Void)?
    @State private var draft: [CGPoint] = []
    @State private var isDrawing = false

    init(
        path: Binding<[CodablePoint]>,
        onRecordedButton: ((MouseTriggerButton) -> Void)? = nil,
        onRecordedPath: (([CGPoint]) -> Void)? = nil
    ) {
        _path = path
        self.onRecordedPath = onRecordedPath
        self.onRecordedButton = onRecordedButton
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let points: [CGPoint] = {
                    if !draft.isEmpty { return draft }
                    return displayPoints(in: geo.size)
                }()
                // Only show the center hint when canvas is empty (no saved path, not drawing).
                let showHint = path.isEmpty && !isDrawing && draft.isEmpty

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.quaternary, lineWidth: 1)

                    // Stroke
                    Path { p in
                        guard let first = points.first else { return }
                        p.move(to: first)
                        for point in points.dropFirst() {
                            p.addLine(to: point)
                        }
                    }
                    .stroke(
                        DrawingStyle.lineSwiftUIColor,
                        style: StrokeStyle(lineWidth: DrawingStyle.lineWidth, lineCap: .round, lineJoin: .round)
                    )

                    // Start point (red)
                    if DrawingStyle.showStartPoint, let start = points.first {
                        Circle()
                            .fill(DrawingStyle.startSwiftUIColor)
                            .frame(width: DrawingStyle.startPointRadius * 2, height: DrawingStyle.startPointRadius * 2)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                            )
                            .overlay(
                                Circle()
                                    .fill(Color.white)
                                    .frame(
                                        width: max(DrawingStyle.startPointRadius * 0.7, 3),
                                        height: max(DrawingStyle.startPointRadius * 0.7, 3)
                                    )
                            )
                            .position(start)
                    }

                    // Live head while drawing
                    if isDrawing, let last = points.last {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(DrawingStyle.lineSwiftUIColor, lineWidth: 2))
                            .position(last)
                    }

                    // Only supported gesture trigger buttons can record on this canvas.
                    if showHint {
                        VStack(spacing: 10) {
                            Image(systemName: "computermouse.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.primary)
                                .symbolRenderingMode(.hierarchical)

                            Text(L10n.string("editor.recordUseMouseButtonTitle"))
                                .font(.title3.weight(.bold))
                                .multilineTextAlignment(.center)

                            Text(L10n.string("editor.recordUseMouseButtonBody"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)

                            Text(L10n.string("editor.recordUseMouseButtonBadge"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(20)
                        .allowsHitTesting(false)
                    }

                    // Capture right, middle and side-button drags locally via AppKit.
                    MouseButtonDrawCatcher(
                        isDrawing: $isDrawing,
                        draft: $draft,
                        onFinished: { points, button in
                            commitDraft(points, button: button)
                        }
                    )
                }
            }
            .frame(minHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(L10n.string("editor.startPointHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(L10n.string("editor.pointCount") + ": \(path.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.string("editor.clear")) {
                    path = []
                    draft = []
                }
            }
        }
    }

    private func commitDraft(_ draftPoints: [CGPoint], button: MouseTriggerButton) {
        guard draftPoints.count >= 2 else {
            draft = []
            return
        }
        // View Y grows downward; live engine uses AppKit Y-up.
        let flipped = flipY(draftPoints)
        guard let recorded = UnistrokeGeometry.recordedPath(flipped) else {
            draft = []
            return
        }
        path = recorded.map(CodablePoint.init)
        onRecordedButton?(button)
        onRecordedPath?(flipped)
        draft = []
    }

    /// Map stored Y-up unit points into view coordinates (Y-down).
    private func displayPoints(in size: CGSize) -> [CGPoint] {
        let pts = path.map(\.cgPoint)
        return GesturePreviewGeometry.aspectFit(points: pts, in: size, padding: 16)
    }

    private func flipY(_ points: [CGPoint]) -> [CGPoint] {
        guard let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max()
        else { return points }
        return points.map { CGPoint(x: $0.x, y: maxY + minY - $0.y) }
    }
}

// MARK: - Local recording canvas

private struct MouseButtonDrawCatcher: NSViewRepresentable {
    @Binding var isDrawing: Bool
    @Binding var draft: [CGPoint]
    var onFinished: ([CGPoint], MouseTriggerButton) -> Void

    func makeNSView(context: Context) -> GestureRecordingCanvasView {
        let view = GestureRecordingCanvasView()
        updateCallbacks(view)
        return view
    }

    func updateNSView(_ view: GestureRecordingCanvasView, context: Context) {
        updateCallbacks(view)
    }

    private func updateCallbacks(_ view: GestureRecordingCanvasView) {
        view.onBegin = { point in
            isDrawing = true
            draft = [point]
        }
        view.onMove = { point in draft.append(point) }
        view.onEnd = { points, button in
            isDrawing = false
            onFinished(points, button)
        }
    }
}

/// Receives local AppKit mouse events only; global capture is suppressed by the editor.
/// Each stroke is owned by its initial button, so another button cannot finish it.
final class GestureRecordingCanvasView: NSView {
    var onBegin: ((CGPoint) -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onEnd: (([CGPoint], MouseTriggerButton) -> Void)?
    private var points: [CGPoint] = []
    private var activeButton: MouseTriggerButton?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    // Deliberately ignore left recording, including a click during another stroke.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) { begin(with: event) }
    override func rightMouseDragged(with event: NSEvent) { move(with: event) }
    override func rightMouseUp(with event: NSEvent) { end(with: event) }
    override func otherMouseDown(with event: NSEvent) { begin(with: event) }
    override func otherMouseDragged(with event: NSEvent) { move(with: event) }
    override func otherMouseUp(with event: NSEvent) { end(with: event) }

    private func begin(with event: NSEvent) {
        guard activeButton == nil,
              let button = MouseTriggerButton(recordingButtonNumber: event.buttonNumber) else { return }
        window?.makeFirstResponder(self)
        activeButton = button
        let point = convert(event.locationInWindow, from: nil)
        points = [point]
        onBegin?(point)
    }

    private func move(with event: NSEvent) {
        guard let activeButton,
              MouseTriggerButton(recordingButtonNumber: event.buttonNumber) == activeButton else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 1 { return }
        points.append(point)
        onMove?(point)
    }

    private func end(with event: NSEvent) {
        guard let button = activeButton,
              MouseTriggerButton(recordingButtonNumber: event.buttonNumber) == button else { return }
        move(with: event)
        let finished = points
        points = []
        activeButton = nil
        onEnd?(finished, button)
    }
}
