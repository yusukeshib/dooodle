import AppKit

extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
}

final class DrawingView: NSView {
    let store: StrokeStore
    var strokes: [Stroke] = []
    private var currentStroke: Stroke?
    private var currentSeq = 0

    /// Current pen settings (set by AppDelegate).
    var penColorHex = "#FF3B30"
    var penWidth: Double = 4

    init(store: StrokeStore) {
        self.store = store
        super.init(frame: .zero)
        strokes = store.loadVisibleStrokes()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for stroke in strokes {
            drawStroke(stroke)
        }
        if let s = currentStroke { drawStroke(s) }
    }

    private func drawStroke(_ stroke: Stroke) {
        guard let first = stroke.vertices.first else { return }
        let path = NSBezierPath()
        path.lineWidth = stroke.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: first.x, y: first.y))
        if stroke.vertices.count == 1 {
            // dot
            path.line(to: NSPoint(x: first.x + 0.1, y: first.y))
        } else {
            for v in stroke.vertices.dropFirst() {
                path.line(to: NSPoint(x: v.x, y: v.y))
            }
        }
        NSColor(hex: stroke.colorHex).setStroke()
        path.stroke()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let now = Date().timeIntervalSince1970
        let id = store.beginStroke(colorHex: penColorHex, width: penWidth, startedAt: now)
        let stroke = Stroke(id: id, startedAt: now, colorHex: penColorHex, width: penWidth)
        currentStroke = stroke
        currentSeq = 0
        appendVertex(point: p, time: now)
    }

    override func mouseDragged(with event: NSEvent) {
        guard currentStroke != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        appendVertex(point: p, time: Date().timeIntervalSince1970)
    }

    override func mouseUp(with event: NSEvent) {
        finishCurrentStroke()
    }

    func finishCurrentStroke() {
        if let s = currentStroke {
            strokes.append(s)
            currentStroke = nil
        }
        needsDisplay = true
    }

    private func appendVertex(point: NSPoint, time: Double) {
        guard let s = currentStroke else { return }
        let v = Vertex(x: point.x, y: point.y, t: time)
        s.vertices.append(v)
        store.addVertex(strokeId: s.id, seq: currentSeq, v)
        currentSeq += 1
        needsDisplay = true
    }

    func clear() {
        store.clearVisible()
        strokes = []
        currentStroke = nil
        needsDisplay = true
    }
}
