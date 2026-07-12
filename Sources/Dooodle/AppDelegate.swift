import AppKit
import ServiceManagement

/// A modifier-style key that shows the overlay while held down.
/// Only modifier keys are offered so normal typing is never swallowed.
struct TriggerKey {
    let label: String
    let keyCode: UInt16
    let flag: NSEvent.ModifierFlags
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var store: StrokeStore!
    private var drawingView: DrawingView!
    private var overlay: OverlayWindow!
    private var monitors: [Any] = []

    // (label, width)
    private let widths: [(String, Double)] = [
        ("Extra Thin (2pt)", 2), ("Thin (4pt)", 4), ("Medium (6pt)", 6), ("Thick (10pt)", 10), ("Extra Thick (16pt)", 16),
    ]
    // (label, hex)
    private let colors: [(String, String)] = [
        ("Red", "#FF3B30"), ("Orange", "#FF9500"), ("Green", "#34C759"),
        ("Blue", "#007AFF"), ("Black", "#000000"),
    ]

    private let triggerKeys: [TriggerKey] = [
        TriggerKey(label: "Fn", keyCode: 63, flag: .function),
        TriggerKey(label: "Right \u{2318} Command", keyCode: 54, flag: .command),
        TriggerKey(label: "Right \u{2325} Option", keyCode: 61, flag: .option),
        TriggerKey(label: "Right \u{2303} Control", keyCode: 62, flag: .control),
        TriggerKey(label: "Left \u{2303} Control", keyCode: 59, flag: .control),
    ]
    private var currentTrigger: TriggerKey!

    private var widthMenuItems: [NSMenuItem] = []
    private var colorMenuItems: [NSMenuItem] = []
    private var triggerMenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = StrokeStore()
        drawingView = DrawingView(store: store)
        overlay = OverlayWindow(view: drawingView)

        // Restore pen settings
        let d = UserDefaults.standard
        let wIdx = d.object(forKey: "penWidthIndex") as? Int ?? 1
        let cIdx = d.object(forKey: "penColorIndex") as? Int ?? 0
        let tIdx = d.object(forKey: "triggerKeyIndex") as? Int ?? 0
        drawingView.penWidth = widths[min(wIdx, widths.count - 1)].1
        drawingView.penColorHex = colors[min(cIdx, colors.count - 1)].1
        currentTrigger = triggerKeys[min(tIdx, triggerKeys.count - 1)]

        setupStatusItem(selectedWidth: wIdx, selectedColor: cIdx, selectedTrigger: tIdx)
        ensureAccessibility()
        installTriggerMonitors()
    }

    // MARK: - Menu

    private func setupStatusItem(selectedWidth: Int, selectedColor: Int, selectedTrigger: Int) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.loopsIcon(active: false)

        let menu = NSMenu()

        let widthMenu = NSMenu()
        for (i, (label, _)) in widths.enumerated() {
            let item = NSMenuItem(title: label, action: #selector(selectWidth(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = i == selectedWidth ? .on : .off
            widthMenu.addItem(item)
            widthMenuItems.append(item)
        }
        let widthRoot = NSMenuItem(title: "Thickness", action: nil, keyEquivalent: "")
        widthRoot.image = NSImage(systemSymbolName: "lineweight", accessibilityDescription: nil)
        widthRoot.submenu = widthMenu

        let clearItem = NSMenuItem(title: "Clear Canvas", action: #selector(clearCanvas), keyEquivalent: "")
        clearItem.target = self
        clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(clearItem)

        menu.addItem(.separator())

        if #available(macOS 14.0, *) {
            menu.addItem(NSMenuItem.sectionHeader(title: "Color"))
        }
        for (i, (label, hex)) in colors.enumerated() {
            let item = NSMenuItem(title: label, action: #selector(selectColor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = i == selectedColor ? .on : .off
            item.image = Self.swatch(NSColor(hex: hex))
            menu.addItem(item)
            colorMenuItems.append(item)
        }

        menu.addItem(.separator())

        menu.addItem(widthRoot)

        menu.addItem(.separator())

        let triggerMenu = NSMenu()
        for (i, key) in triggerKeys.enumerated() {
            let item = NSMenuItem(title: key.label, action: #selector(selectTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = i == selectedTrigger ? .on : .off
            triggerMenu.addItem(item)
            triggerMenuItems.append(item)
        }
        let triggerRoot = NSMenuItem(title: "Trigger Key", action: nil, keyEquivalent: "")
        triggerRoot.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        triggerRoot.submenu = triggerMenu
        menu.addItem(triggerRoot)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(loginItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        return NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    @objc private func selectWidth(_ sender: NSMenuItem) {
        drawingView.penWidth = widths[sender.tag].1
        UserDefaults.standard.set(sender.tag, forKey: "penWidthIndex")
        widthMenuItems.forEach { $0.state = $0 == sender ? .on : .off }
    }

    @objc private func selectColor(_ sender: NSMenuItem) {
        drawingView.penColorHex = colors[sender.tag].1
        UserDefaults.standard.set(sender.tag, forKey: "penColorIndex")
        colorMenuItems.forEach { $0.state = $0 == sender ? .on : .off }
    }

    @objc private func clearCanvas() {
        drawingView.clear()
    }

    @objc private func selectTrigger(_ sender: NSMenuItem) {
        // If the overlay is showing, hide it before switching triggers.
        drawingView.finishCurrentStroke()
        overlay.hide()
        currentTrigger = triggerKeys[sender.tag]
        UserDefaults.standard.set(sender.tag, forKey: "triggerKeyIndex")
        triggerMenuItems.forEach { $0.state = $0 == sender ? .on : .off }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            NSLog("Dooodle: launch-at-login toggle failed: \(error)")
        }
    }

    // MARK: - Trigger key

    private func ensureAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSLog("Dooodle: waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility)")
        }
    }

    private func installTriggerMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, let trigger = self.currentTrigger,
                  event.keyCode == trigger.keyCode else { return }
            self.triggerChanged(down: event.modifierFlags.contains(trigger.flag))
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) {
            monitors.append(global)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
        if let local { monitors.append(local) }
    }

    private func triggerChanged(down: Bool) {
        if down {
            overlay.show()
        } else {
            drawingView.finishCurrentStroke()
            overlay.hide()
        }
        updateStatusIcon(active: down)
    }

    /// Red ink loops while the overlay is active, template (auto light/dark) otherwise.
    private func updateStatusIcon(active: Bool) {
        statusItem.button?.image = Self.loopsIcon(active: active)
    }

    /// The "ooo" loop scribble from the app icon, sized for the menu bar.
    /// Same prolate cycloid as Scripts/make_icon.swift.
    private static func loopsIcon(active: Bool) -> NSImage {
        let size = NSSize(width: 24, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let a: CGFloat = 46, b: CGFloat = 118, loops = 3, steps = 240
            let t0 = -CGFloat.pi * 0.55
            // loops form around t = 0, 2π, 4π, ... so N loops span (N-1) full periods
            // extend past the last loop so the stroke flicks out instead of ending on the circle
            let t1 = CGFloat(loops - 1) * 2 * .pi + CGFloat.pi * 0.85
            let tilt: CGFloat = -6 * .pi / 180 // same hand-drawn tilt as the app icon
            var pts: [NSPoint] = []
            for i in 0...steps {
                let t = t0 + (t1 - t0) * CGFloat(i) / CGFloat(steps)
                let x = a * t - b * sin(t), y = -b * cos(t)
                pts.append(NSPoint(
                    x: x * cos(tilt) - y * sin(tilt),
                    y: x * sin(tilt) + y * cos(tilt)))
            }
            let xs = pts.map(\.x), ys = pts.map(\.y)
            let w = xs.max()! - xs.min()!, h = ys.max()! - ys.min()!
            let lineWidth: CGFloat = 2.2
            let scale = min((rect.width - lineWidth) / w, (rect.height - lineWidth) / h)
            let cx = (xs.max()! + xs.min()!) / 2, cy = (ys.max()! + ys.min()!) / 2
            let path = NSBezierPath()
            for (i, p) in pts.enumerated() {
                let pt = NSPoint(
                    x: rect.midX + (p.x - cx) * scale,
                    y: rect.midY + (p.y - cy) * scale)
                i == 0 ? path.move(to: pt) : path.line(to: pt)
            }
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            (active ? NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1) : .black).setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = !active // template = adapts to light/dark; red stays red
        image.accessibilityDescription = "Dooodle"
        return image
    }
}
