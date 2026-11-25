import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if CLI.handles(arguments) {
            Task { @MainActor in exit(await CLI.run(arguments)) }
            dispatchMain()
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
        app.run()
    }
}

/// A floating panel that stays visible when you click into another app (Meet),
/// shows over full-screen apps and can take typing without activating RefineBar.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Called whenever the panel hides: the menu bar icon, the menu, Esc or the close button.
    var onHide: (() -> Void)?

    override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible
        super.orderOut(sender)
        if wasVisible { onHide?() }
    }

    override func close() {
        let wasVisible = isVisible
        super.close()
        if wasVisible { onHide?() }
    }

    /// A menu-bar-only app has no Edit menu, which is where ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z
    /// normally come from, so text fields would ignore them. Send them to the
    /// focused field directly. The panel's own shortcuts (⌘R, ⇧⌘C) go first.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let shift = flags.contains(.shift)
        let action: Selector?
        switch (key, shift) {
        case ("v", false): action = #selector(NSText.paste(_:))
        case ("c", false): action = #selector(NSText.copy(_:))
        case ("x", false): action = #selector(NSText.cut(_:))
        case ("a", false): action = #selector(NSText.selectAll(_:))
        case ("z", false): action = Selector(("undo:"))
        case ("z", true): action = Selector(("redo:"))
        default: action = nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)  // Esc closes it
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var model: ViewModel!
    private var hasPositioned = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = ViewModel()
        model.onRecordingChange = { [weak self] recording in self?.updateIcon(recording: recording) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "RefineBar: say it in English"
        }
        updateIcon(recording: false)

        let hosting = NSHostingController(rootView: PanelView(model: model))
        hosting.sizingOptions = [.preferredContentSize]  // the panel follows the SwiftUI size

        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        // Each time it opens, it starts empty.
        panel.onHide = { [weak self] in self?.model.panelClosed() }

        LoginItem.enableOnFirstRun()

        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshot(to: CommandLine.arguments[i + 1])
            return
        }

        // First run: open the panel so the API key can be entered right away. Wait a
        // moment so the menu bar icon has its final position to open under.
        if Keychain.apiKey() == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showPanel() }
        }
    }

    /// Debug aid: renders the panel offscreen to a PNG and quits. No screen
    /// recording permission needed. `RefineBar --snapshot out.png [--settings]`
    private func snapshot(to path: String) {
        model.showSettings = CommandLine.arguments.contains("--settings")
        if let i = CommandLine.arguments.firstIndex(of: "--draft"), i + 1 < CommandLine.arguments.count {
            model.draft = CommandLine.arguments[i + 1]
        }
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [panel] in
            guard let panel, let view = panel.contentView?.superview,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // Open under the menu bar icon the first time; after that it stays where
        // you dragged it (e.g. next to the camera).
        if !hasPositioned, let button = statusItem.button, let buttonWindow = button.window,
           let screen = buttonWindow.screen ?? NSScreen.main {
            let iconFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let visible = screen.visibleFrame
            let size = panel.frame.size
            // Right under the icon; if the icon isn't laid out yet, the top-right corner.
            let iconReady = iconFrame.minY > visible.midY
            var origin = iconReady
                ? NSPoint(x: iconFrame.midX - size.width / 2, y: iconFrame.minY - size.height - 6)
                : NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 6)
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            panel.setFrameTopLeftPoint(NSPoint(x: origin.x, y: origin.y + size.height))
            hasPositioned = iconReady
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: panel.isVisible ? "Hide panel" : "Show panel", action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit RefineBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // keep left click for the panel
    }

    @objc private func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { showPanel() }
    }

    private func updateIcon(recording: Bool) {
        let name = recording ? "mic.circle.fill" : "character.bubble"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "RefineBar")
        image?.isTemplate = !recording
        statusItem.button?.image = recording ? image?.withSymbolConfiguration(.init(paletteColors: [.white, .systemRed])) : image
    }
}
