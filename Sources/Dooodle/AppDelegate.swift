import AppKit
import ServiceManagement

/// A modifier-style key (or combination) that shows the overlay while held down.
/// Only modifier keys are offered so normal typing is never swallowed.
struct TriggerKey {
    let label: String
    /// Set for single-key triggers (side-specific, e.g. Right \u{2318}).
    /// nil for multi-modifier combos (side-agnostic, matched by flags only).
    let keyCode: UInt16?
    let flags: NSEvent.ModifierFlags
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
        TriggerKey(label: "Fn", keyCode: 63, flags: .function),
        TriggerKey(label: "Right \u{2318} Command", keyCode: 54, flags: .command),
        TriggerKey(label: "Right \u{2325} Option", keyCode: 61, flags: .option),
        TriggerKey(label: "Right \u{2303} Control", keyCode: 62, flags: .control),
        TriggerKey(label: "Left \u{2303} Control", keyCode: 59, flags: .control),
    ]
    private var currentTrigger: TriggerKey!
    private var customTrigger: TriggerKey?
    private var customTriggerItem: NSMenuItem!
    private var isRecordingTrigger = false
    private var recordingMonitors: [Any] = []
    private var recordingPanel: NSPanel?
    private var recordingLabel: NSTextField?
    private var recordingCloseObserver: NSObjectProtocol?
    private var triggerIsDown = false

    /// The modifier flags a trigger may consist of.
    private static let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]

    private static func comboLabel(for flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("\u{2303} Control") }
        if flags.contains(.option) { parts.append("\u{2325} Option") }
        if flags.contains(.shift) { parts.append("\u{21E7} Shift") }
        if flags.contains(.command) { parts.append("\u{2318} Command") }
        if flags.contains(.function) { parts.append("Fn") }
        return parts.joined(separator: " + ")
    }

    private static func flagCount(_ flags: NSEvent.ModifierFlags) -> Int {
        [NSEvent.ModifierFlags.command, .option, .control, .shift, .function]
            .filter { flags.contains($0) }.count
    }

    /// Every modifier key we can identify from a `flagsChanged` event.
    /// Caps Lock is excluded on purpose (it toggles instead of being held).
    private static let recordableModifiers: [UInt16: (label: String, flag: NSEvent.ModifierFlags)] = [
        54: ("Right \u{2318} Command", .command),
        55: ("Left \u{2318} Command", .command),
        56: ("Left \u{21E7} Shift", .shift),
        60: ("Right \u{21E7} Shift", .shift),
        58: ("Left \u{2325} Option", .option),
        61: ("Right \u{2325} Option", .option),
        59: ("Left \u{2303} Control", .control),
        62: ("Right \u{2303} Control", .control),
        63: ("Fn", .function),
    ]

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
        var tIdx = d.object(forKey: "triggerKeyIndex") as? Int ?? 0
        drawingView.penWidth = widths[min(wIdx, widths.count - 1)].1
        drawingView.penColorHex = colors[min(cIdx, colors.count - 1)].1

        // Restore a previously recorded custom trigger, if any.
        let storedFlags = (d.object(forKey: "customTriggerFlags") as? Int)
            .map { NSEvent.ModifierFlags(rawValue: UInt($0)).intersection(Self.relevantFlags) }
        if let code = d.object(forKey: "customTriggerKeyCode") as? Int,
           let info = Self.recordableModifiers[UInt16(code)] {
            customTrigger = TriggerKey(label: info.label, keyCode: UInt16(code), flags: info.flag)
        } else if let flags = storedFlags, !flags.isEmpty {
            customTrigger = TriggerKey(label: Self.comboLabel(for: flags), keyCode: nil, flags: flags)
        }
        if tIdx == triggerKeys.count, let custom = customTrigger {
            currentTrigger = custom
        } else {
            tIdx = min(tIdx, triggerKeys.count - 1)
            currentTrigger = triggerKeys[tIdx]
        }

        setupStatusItem(selectedWidth: wIdx, selectedColor: cIdx, selectedTrigger: tIdx)
        ensureAccessibility()
        installTriggerMonitors()
    }

    // MARK: - Menu

    private func setupStatusItem(selectedWidth: Int, selectedColor: Int, selectedTrigger: Int) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.loopsIcon(tint: nil)

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
        triggerMenu.addItem(.separator())
        customTriggerItem = NSMenuItem(title: Self.customItemTitle(for: customTrigger),
                                       action: #selector(recordCustomTrigger(_:)), keyEquivalent: "")
        customTriggerItem.target = self
        customTriggerItem.tag = triggerKeys.count
        customTriggerItem.state = selectedTrigger == triggerKeys.count && customTrigger != nil ? .on : .off
        triggerMenu.addItem(customTriggerItem)
        triggerMenuItems.append(customTriggerItem)
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
        cancelTriggerRecording()
        // If the overlay is showing, hide it before switching triggers.
        drawingView.finishCurrentStroke()
        overlay.hide()
        currentTrigger = triggerKeys[sender.tag]
        UserDefaults.standard.set(sender.tag, forKey: "triggerKeyIndex")
        triggerMenuItems.forEach { $0.state = $0 == sender ? .on : .off }
    }

    // MARK: - Custom trigger recording

    private static func customItemTitle(for trigger: TriggerKey?) -> String {
        if let trigger { return "Custom: \(trigger.label)" }
        return "Custom\u{2026}"
    }

    @objc private func recordCustomTrigger(_ sender: NSMenuItem) {
        if isRecordingTrigger {
            cancelTriggerRecording()
            return
        }
        drawingView.finishCurrentStroke()
        overlay.hide()
        isRecordingTrigger = true
        customTriggerItem.title = "Hold modifier key(s)\u{2026} (Esc to cancel)"
        showRecordingPanel()

        // Accumulate every modifier held during the gesture; commit on full release.
        var recordedFlags: NSEvent.ModifierFlags = []
        var lastKeyCode: UInt16?
        let capture: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.isRecordingTrigger else { return }
            let pressed = event.modifierFlags.intersection(Self.relevantFlags)
            if pressed.isEmpty {
                // Everything released — commit what was held.
                guard !recordedFlags.isEmpty else { return }
                let trigger: TriggerKey
                if Self.flagCount(recordedFlags) == 1, let code = lastKeyCode,
                   let info = Self.recordableModifiers[code] {
                    // Single modifier: keep side-specific precision (e.g. Right \u{2318}).
                    trigger = TriggerKey(label: info.label, keyCode: code, flags: info.flag)
                } else {
                    trigger = TriggerKey(label: Self.comboLabel(for: recordedFlags),
                                         keyCode: nil, flags: recordedFlags)
                }
                self.finishTriggerRecording(trigger)
            } else {
                recordedFlags.formUnion(pressed)
                if Self.recordableModifiers[event.keyCode] != nil { lastKeyCode = event.keyCode }
                self.recordingLabel?.stringValue = Self.comboLabel(for: recordedFlags)
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: capture) {
            recordingMonitors.append(global)
        }
        let localFlags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            capture(event)
            return event
        }
        if let localFlags { recordingMonitors.append(localFlags) }
        // Esc cancels recording (only reachable via a local keyDown monitor).
        let localKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.cancelTriggerRecording()
                return nil
            }
            return event
        }
        if let localKey { recordingMonitors.append(localKey) }
    }

    private func finishTriggerRecording(_ trigger: TriggerKey) {
        stopRecordingMonitors()
        isRecordingTrigger = false
        customTrigger = trigger
        currentTrigger = trigger
        let d = UserDefaults.standard
        d.set(Int(trigger.flags.rawValue), forKey: "customTriggerFlags")
        if let code = trigger.keyCode {
            d.set(Int(code), forKey: "customTriggerKeyCode")
        } else {
            d.removeObject(forKey: "customTriggerKeyCode")
        }
        d.set(triggerKeys.count, forKey: "triggerKeyIndex")
        customTriggerItem.title = Self.customItemTitle(for: trigger)
        triggerMenuItems.forEach { $0.state = $0 == customTriggerItem ? .on : .off }
        // Show what was captured, then dismiss the panel shortly after.
        recordingLabel?.stringValue = "\u{2713} \(trigger.label)"
        recordingLabel?.textColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.closeRecordingPanel()
        }
    }

    private func cancelTriggerRecording() {
        guard isRecordingTrigger else { return }
        stopRecordingMonitors()
        isRecordingTrigger = false
        customTriggerItem.title = Self.customItemTitle(for: customTrigger)
        closeRecordingPanel()
    }

    // MARK: Recording panel UI

    private func showRecordingPanel() {
        closeRecordingPanel()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 170),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        panel.title = "Record Trigger Key"
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let label = NSTextField(labelWithString: "Hold modifier key(s)\u{2026}")
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.alignment = .center

        let hint = NSTextField(labelWithString: "\u{2318} \u{2325} \u{2303} \u{21E7} Fn — combos OK (e.g. \u{2318}+\u{2325}) — release to set")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        let cancelHint = NSTextField(labelWithString: "Esc to cancel")
        cancelHint.font = .systemFont(ofSize: 11)
        cancelHint.textColor = .tertiaryLabelColor
        cancelHint.alignment = .center

        let warning = NSTextField(
            wrappingLabelWithString: "Tip: keys you use for shortcuts (e.g. Left \u{2318}) will pop the overlay every time you press them.")
        warning.font = .systemFont(ofSize: 11)
        warning.textColor = .secondaryLabelColor
        warning.alignment = .center
        warning.preferredMaxLayoutWidth = 300

        let stack = NSStackView(views: [label, hint, warning, cancelHint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        panel.contentView = content

        // Closing the panel with its close button cancels the recording.
        recordingCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.cancelTriggerRecording()
        }

        recordingPanel = panel
        recordingLabel = label
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    private func closeRecordingPanel() {
        guard let panel = recordingPanel else { return }
        recordingPanel = nil
        recordingLabel = nil
        if let observer = recordingCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            recordingCloseObserver = nil
        }
        panel.orderOut(nil)
        // Give focus back to whatever app the user was in — otherwise
        // keystrokes go nowhere while Dooodle stays active with no window.
        NSApp.hide(nil)
    }

    private func stopRecordingMonitors() {
        recordingMonitors.forEach { NSEvent.removeMonitor($0) }
        recordingMonitors.removeAll()
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
            guard let self, !self.isRecordingTrigger, let trigger = self.currentTrigger else { return }
            let down: Bool
            if let code = trigger.keyCode {
                // Single-key trigger: side-specific match on the exact key.
                guard event.keyCode == code else { return }
                down = event.modifierFlags.contains(trigger.flags)
            } else {
                // Combo trigger: all recorded modifiers must be held (any side).
                let pressed = event.modifierFlags.intersection(Self.relevantFlags)
                down = pressed.isSuperset(of: trigger.flags)
            }
            guard down != self.triggerIsDown else { return }
            self.triggerIsDown = down
            self.triggerChanged(down: down)
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

    /// Idle: a calm monochrome scribble that adapts to light/dark (pen "capped").
    /// Active: the same scribble inked in the *current pen color* with a fresh
    /// ink-tip dot, so the menu bar previews exactly what you're drawing with.
    private func updateStatusIcon(active: Bool) {
        let tint = active ? NSColor(hex: drawingView.penColorHex) : nil
        statusItem.button?.image = Self.loopsIcon(tint: tint)
    }

    /// The "ooo" loop scribble from the app icon, sized for the menu bar.
    /// Same prolate cycloid as Scripts/make_icon.swift.
    /// `tint == nil` renders a template (idle); a non-nil tint inks it live.
    private static func loopsIcon(tint: NSColor?) -> NSImage {
        let active = tint != nil
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
            // Slightly bolder while inking so "live" reads at a glance.
            let lineWidth: CGFloat = active ? 2.6 : 2.1
            let tipR: CGFloat = 2.0 // ink-tip dot radius (active only)
            let margin = max(lineWidth, active ? tipR * 2 : lineWidth)
            let scale = min((rect.width - margin) / w, (rect.height - margin) / h)
            let cx = (xs.max()! + xs.min()!) / 2, cy = (ys.max()! + ys.min()!) / 2
            let place = { (p: NSPoint) -> NSPoint in
                NSPoint(x: rect.midX + (p.x - cx) * scale,
                        y: rect.midY + (p.y - cy) * scale)
            }
            let path = NSBezierPath()
            for (i, p) in pts.enumerated() {
                let pt = place(p)
                i == 0 ? path.move(to: pt) : path.line(to: pt)
            }
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            (tint ?? .black).setStroke()
            path.stroke()
            // Fresh ink tip at the end of the flick — signals "now writing".
            if let tint, let last = pts.last {
                let tip = place(last)
                tint.setFill()
                NSBezierPath(ovalIn: NSRect(x: tip.x - tipR, y: tip.y - tipR,
                                            width: tipR * 2, height: tipR * 2)).fill()
            }
            return true
        }
        image.isTemplate = !active // template = adapts to light/dark; inked color stays
        image.accessibilityDescription = active ? "Dooodle (drawing)" : "Dooodle"
        return image
    }
}
