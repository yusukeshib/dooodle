import AppKit
import ServiceManagement

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

    private var widthMenuItems: [NSMenuItem] = []
    private var colorMenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = StrokeStore()
        drawingView = DrawingView(store: store)
        overlay = OverlayWindow(view: drawingView)

        // Restore pen settings
        let d = UserDefaults.standard
        let wIdx = d.object(forKey: "penWidthIndex") as? Int ?? 1
        let cIdx = d.object(forKey: "penColorIndex") as? Int ?? 0
        drawingView.penWidth = widths[min(wIdx, widths.count - 1)].1
        drawingView.penColorHex = colors[min(cIdx, colors.count - 1)].1

        setupStatusItem(selectedWidth: wIdx, selectedColor: cIdx)
        ensureAccessibility()
        installFnMonitors()
    }

    // MARK: - Menu

    private func setupStatusItem(selectedWidth: Int, selectedColor: Int) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "scribble.variable", accessibilityDescription: "Dooodle")

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
        let widthRoot = NSMenuItem(title: "Width", action: nil, keyEquivalent: "")
        widthRoot.image = NSImage(systemSymbolName: "lineweight", accessibilityDescription: nil)
        widthRoot.submenu = widthMenu
        menu.addItem(widthRoot)

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

        let clearItem = NSMenuItem(title: "Clear Canvas", action: #selector(clearCanvas), keyEquivalent: "")
        clearItem.target = self
        clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(clearItem)

        menu.addItem(.separator())

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

    // MARK: - Fn key

    private func ensureAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSLog("Dooodle: waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility)")
        }
    }

    private func installFnMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == 63 else { return } // fn key
            let fnDown = event.modifierFlags.contains(.function)
            self?.fnChanged(down: fnDown)
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

    private func fnChanged(down: Bool) {
        if down {
            overlay.show()
        } else {
            drawingView.finishCurrentStroke()
            overlay.hide()
        }
    }
}
