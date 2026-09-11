import SwiftUI
import AppKit

@main
struct HingeScapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: DesktopWindow?
    private var model: AppModel?
    private var screenObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var globalController: GlobalDesktopController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        // Never reset TCC automatically. An ad-hoc build gets a new code
        // identity on every rebuild; resetting here revoked a working grant and
        // made startCapture fail, whose error path restores the setup window.
        model.globalStatus = "Live Desktop requires Screen Recording permission; macOS will ask when enabled"
        // No screen at launch (e.g. mid display change) must not crash; the
        // screen-parameters observer below resizes the window later.
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = DesktopWindow(contentRect: frame, styleMask: [.borderless],
                                   backing: .buffered, defer: false)
        window.title = "HingeScape"
        if let iconURL = Bundle.main.url(forResource: "HingeScape", withExtension: "png") {
            NSApp.applicationIconImage = NSImage(contentsOf: iconURL)
        }
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RootView(model: model)
            .ignoresSafeArea().preferredColorScheme(.dark))
        self.window = window
        let globalController = GlobalDesktopController(model: model, setupWindow: window)
        self.globalController = globalController
        model.startGlobal = { [weak globalController] in globalController?.start() }
        model.previewGlobal = { [weak globalController] in globalController?.preview() }
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        NSApp.setActivationPolicy(.regular)
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Handle before AppKit's default Command-H (which hides the whole app).
        // Restricted to this window so file dialogs retain their own shortcuts.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow === self.window, let model = self.model else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "h" {
                if model.page == .test && !event.isARepeat { model.controlsHidden.toggle() }
                return nil
            }
            guard model.page == .test else { return event }
            if modifiers == .command {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "k":
                    if !event.isARepeat { model.saveOpenAngle() }
                    return nil
                case "b":
                    if !event.isARepeat { model.showOriginal.toggle() }
                    return nil
                default: break
                }
            }
            if event.keyCode == 53 {
                model.controlsHidden = false
                return nil
            }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.globalController?.screenConfigurationChanged() }
            guard let window = self?.window, let screen = window.screen ?? NSScreen.main else { return }
            window.setFrame(screen.frame, display: true)
        }
    }

    @MainActor @objc private func openSettings() {
        globalController?.showSetup()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // AppKit may issue a reopen when the foreground setup window is ordered
        // out. Live mode deliberately has no normal window; keep it that way.
        if globalController?.keepsSetupHidden == true { return false }
        globalController?.showSetup()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
