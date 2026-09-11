import AppKit
import ScreenCaptureKit
import Carbon
import CoreMedia

// Capture and render are local only. No recordings or network output.
@MainActor
final class GlobalDesktopController: NSObject, @preconcurrency SCStreamOutput, SCStreamDelegate {
    private let model: AppModel
    private weak var setupWindow: NSWindow?
    private var overlay: NSWindow?
    private var renderer: GlassMetalView?
    private var stream: SCStream?
    private var timer: Timer?
    private var statusItem: NSStatusItem!
    // ⌘⇧Esc lives for the whole app; ⌘⇧G/⌘⇧K only while live mode is wanted.
    private var emergencyHotKey: EventHotKeyRef?
    private var sessionHotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var generation = 0
    private var starting = false
    // Timeouts use monotonic time (see Monotonic) so clock changes can't skew them.
    private var startedAt = Monotonic.now
    private var receivedFrame = false
    // False after anything that can make the last texture misleading (Space
    // change, sleep, lock, display change, restart); the next frame sets it.
    private var frameIsCurrent = false
    private var pointerActivity = PointerActivity()
    // Shows the effect only while the lid moves; also runs previews.
    private var effectGate = EffectGate()
    // Kept to change the frame rate on the running stream.
    private var captureConfig: SCStreamConfiguration?
    private var captureIsFast = false
    private var captureRateChanging = false
    private var requestedVisible = false
    private var overlayVisibilityGeneration = 0
    private var overlayIsHiding = false
    private var previewRequested = false
    private var frameCount = 0
    private var capturedDisplayID: CGDirectDisplayID?
    private var statusLine: NSMenuItem!
    private var statusTick = 0
    private var observers: [NSObjectProtocol] = []
    private var resumeWanted = false {
        didSet {
            guard resumeWanted != oldValue else { return }
            // Claim ⌘⇧G/⌘⇧K only while live mode is wanted, so Finder, Xcode
            // and other apps keep those shortcuts the rest of the time.
            setSessionHotKeys(enabled: resumeWanted)
            model.sensor.setFastPolling(resumeWanted, for: "global")
        }
    }
    private var sleepReasons = Set<String>()
    private var recoveryTimer: Timer?
    private var recoveryFailures = 0
    private var nextRecoveryAttempt = -TimeInterval.infinity
    // The setup window is hidden during capture. After wake, on-screen content
    // may omit our process, but the SCApplication from this process remains valid.
    private var captureApplication: SCRunningApplication?

    /// Reopen events can be delivered when the last normal window disappears.
    /// While live mode owns the screen, they must not restore the setup page.
    var keepsSetupHidden: Bool { resumeWanted || stream != nil || starting }

    init(model: AppModel, setupWindow: NSWindow) {
        self.model = model
        self.setupWindow = setupWindow
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "HingeScape", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            icon.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = icon
        }
        statusItem.button?.setAccessibilityLabel("HingeScape")
        let menu = NSMenu()
        statusLine = NSMenuItem(title: "Not Running", action: nil, keyEquivalent: "")
        menu.addItem(statusLine)
        for (title, action) in [
            ("Preview Live Effect (8 Seconds)", #selector(preview)),
            ("Start / Stop Global Effect (⌘⇧G While Running)", #selector(toggle)),
            ("Save Current Fully Open Angle (⌘⇧K While Running)", #selector(calibrate)),
            ("Open Settings   ⌘⇧Esc", #selector(showSetup)),
            ("Quit HingeScape", #selector(quit))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        statusItem.menu = menu
        registerKeys()
        for (name, key) in [(NSWorkspace.willSleepNotification, "system"),
                            (NSWorkspace.screensDidSleepNotification, "display"),
                            (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.sleepReasons.insert(key)
                        self?.frameIsCurrent = false
                        self?.suspend(reason: "Paused · Opens automatically after wake")
                    }
                })
        }
        // A plain screen lock posts none of the workspace notifications above.
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleepReasons.insert("lock")
                self?.frameIsCurrent = false
                self?.suspend(reason: "Screen locked · Resumes automatically after unlock")
            }
        })
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleepReasons.remove("lock")
                self?.recoverIfReady()
            }
        })
        for (name, key) in [(NSWorkspace.didWakeNotification, "system"),
                            (NSWorkspace.screensDidWakeNotification, "display"),
                            (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.sleepReasons.remove(key)
                        self?.recoverIfReady()
                    }
                })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Keep the texture, but don't show it again until a frame from the
            // new Space arrives. Sleep, session and lock observers hide it too.
            MainActor.assumeIsolated {
                self?.frameIsCurrent = false
                self?.cancelOverlayTransition()
                self?.overlay?.orderOut(nil)
                self?.startedAt = Monotonic.now
            }
        })
    }

    @objc func preview() {
        if stream != nil {
            effectGate.requestPreview(at: Monotonic.now)
        } else {
            previewRequested = true
            start()
            // start() may decline (no sensor, permissions pending, asleep);
            // don't let the request fire on some later start.
            if !starting { previewRequested = false }
        }
    }

    @objc private func toggle() {
        if stream != nil || starting || resumeWanted { stop(reason: "Global effect stopped") } else { start() }
    }
    @objc private func calibrate() {
        guard model.sensor.isAvailable else { return }
        // Global mode always calibrates the real hinge, never a preview slider.
        model.useSensor = true
        // The sensor idles when nothing needs live angles; read it now.
        model.sensor.refresh()
        model.saveOpenAngle()
    }
    @objc func showSetup() {
        stop(reason: "Global effect stopped")
        model.returnToSetup()
        NSApp.setActivationPolicy(.regular)
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quit() {
        stop(reason: "Stopped")
        NSApp.terminate(nil)
    }

    func start(automatically: Bool = false) {
        guard !model.permissionsPreparing else { return }
        guard !starting && stream == nil else { return }
        guard emergencyHotKey != nil else {
            model.globalStatus = "Emergency-stop shortcut registration failed; overlay not enabled"
            return
        }
        guard model.sensor.isAvailable else {
            model.globalStatus = "No hinge sensor is available; use Screenshot Test mode"
            return
        }
        if !automatically {
            recoveryFailures = 0
            nextRecoveryAttempt = -.infinity
        }
        resumeWanted = true
        guard sleepReasons.isEmpty else {
            suspend(reason: "Waiting for the display to wake before resuming")
            return
        }
        starting = true
        generation += 1
        let token = generation
        model.globalStatus = "Requesting desktop capture · Allow Screen Recording if prompted"
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard token == generation else { return }
                // Target the built-in panel. External displays aren't hinge-driven.
                guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
                      let screen = NSScreen.screens.first(where: {
                          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
                      }) else { throw GlobalError.noInternalDisplay }
                let ownPID = ProcessInfo.processInfo.processIdentifier
                if let application = content.applications.first(where: { $0.processID == ownPID }) {
                    captureApplication = application
                }
                guard let application = captureApplication, application.processID == ownPID else {
                    throw GlobalError.cannotExcludeSelf
                }
                let excluded = [application]
                let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
                let config = SCStreamConfiguration()
                // Logical resolution for prototype power budget; native panel output.
                config.width = Int(screen.frame.width)
                config.height = Int(screen.frame.height)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                // Starts at the idle rate; update() raises it while the effect shows.
                config.minimumFrameInterval = CMTime(value: 1, timescale: Self.idleCaptureFPS)
                config.queueDepth = 3
                config.showsCursor = false
                config.capturesAudio = false
                let renderer = self.renderer ?? GlassMetalView()
                guard renderer.device != nil else { throw GlobalError.noGPU }
                let overlay = (self.overlay as? NSPanel) ?? NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                overlay.hidesOnDeactivate = false
                overlay.becomesKeyOnlyIfNeeded = true
                overlay.isReleasedWhenClosed = false
                overlay.backgroundColor = .black
                overlay.hasShadow = false
                overlay.ignoresMouseEvents = true
                // A nonactivating panel may join other applications' native
                // fullscreen spaces without taking their keyboard focus.
                // Include Dock/Launchpad, menu bar and ordinary pop-up menus in
                // the live composite. Keep below screen saver/security surfaces.
                // Mouse events still pass through; global emergency keys remain.
                overlay.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
                overlay.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications,
                                              .fullScreenAuxiliary, .stationary, .ignoresCycle]
                overlay.contentView = renderer
                overlay.setFrame(screen.frame, display: false)
                self.renderer = renderer
                self.overlay = overlay
                capturedDisplayID = display.displayID
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
                self.stream = stream
                captureConfig = config
                captureIsFast = false
                captureRateChanging = false
                frameCount = 0
                setupWindow?.orderOut(nil)
                NSApp.presentationOptions = []
                startedAt = Monotonic.now
                if !automatically { receivedFrame = false }
                frameIsCurrent = false
                try await stream.startCapture()
                guard token == generation else {
                    try? await stream.stopCapture()
                    return
                }
                starting = false
                if !sleepReasons.isEmpty {
                    suspend(reason: "Frame retained · Waiting for the display to wake")
                    return
                }
                recoveryTimer?.invalidate()
                recoveryTimer = nil
                if previewRequested {
                    effectGate.requestPreview(at: Monotonic.now)
                    previewRequested = false
                }
                model.globalRunning = true
                model.globalStatus = "Live Desktop enabled · ⌘⇧Esc stops and opens Settings"
                statusItem.button?.toolTip = model.globalStatus
                // Live mode is a background/menu-bar utility. Remaining a
                // regular foreground app lets AppKit reopen the hidden setup
                // window when the overlay is dismissed.
                NSApp.setActivationPolicy(.accessory)
                NSLog("Global capture started")
                resumeRendering()
            } catch {
                guard token == generation else { return }
                let failedStream = self.stream
                self.stream = nil
                starting = false
                if let failedStream { Task { try? await failedStream.stopCapture() } }
                if automatically && recoveryFailures < 3 {
                    recoveryFailures += 1
                    nextRecoveryAttempt = Monotonic.now + Double(recoveryFailures)
                    suspend(reason: "Retrying after wake (\(recoveryFailures)/3): \(error.localizedDescription)")
                    return
                }
                stop(reason: "Could not start: \(error.localizedDescription). Check System Settings → Privacy & Security → Screen Recording.")
                NSApp.setActivationPolicy(.regular)
                setupWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func suspend(reason: String) {
        guard resumeWanted || stream != nil || starting else { return }
        // Suspension keeps the window, GPU textures and a healthy stream, but
        // always hides the overlay: with the update loop stopped, a frozen
        // picture over a click-through window would hide the real UI.
        timer?.invalidate()
        timer = nil
        renderer?.isPaused = true
        cancelOverlayTransition()
        overlay?.orderOut(nil)
        model.globalRunning = true
        model.globalStatus = reason
        statusLine?.title = reason
        NSLog("Global suspended (resources retained): %@", reason)
        if recoveryTimer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.recoverIfReady() }
            }
            recoveryTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func recoverIfReady() {
        let now = Monotonic.now
        guard resumeWanted, sleepReasons.isEmpty, !starting,
              now >= nextRecoveryAttempt,
              !model.permissionsPreparing, model.sensor.isAvailable,
              now - model.sensor.lastSuccessfulUpdate < 0.5,
              NSScreen.screens.contains(where: {
                  guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
                  return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0
              }) else { return }
        if stream != nil {
            recoveryTimer?.invalidate()
            recoveryTimer = nil
            startedAt = now
            resumeRendering()
            model.globalStatus = "Resumed after wake · Window and frame retained"
            NSLog("Global resumed using existing stream and renderer")
            return
        }
        // Wake recovery must never open a fresh permission prompt by itself.
        guard CGPreflightScreenCaptureAccess() else {
            stop(reason: "Screen Recording permission unavailable · Enable the effect manually and allow access")
            return
        }
        start(automatically: true)
    }

    private func resumeRendering() {
        renderer?.isPaused = false
        // Fresh baseline: pointer use while suspended isn't new activity.
        pointerActivity = PointerActivity()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        update()
    }

    func stop(reason: String) {
        resumeWanted = false
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        generation += 1
        starting = false
        cancelOverlayTransition()
        overlay?.orderOut(nil)
        overlay = nil
        renderer = nil
        capturedDisplayID = nil
        timer?.invalidate()
        timer = nil
        let oldStream = stream
        stream = nil
        if let oldStream { Task { try? await oldStream.stopCapture() } }
        captureConfig = nil
        captureIsFast = false
        captureRateChanging = false
        receivedFrame = false
        frameIsCurrent = false
        requestedVisible = false
        previewRequested = false
        effectGate = EffectGate()
        model.globalRunning = false
        model.globalStatus = reason
        statusItem?.button?.toolTip = reason
        statusItem?.button?.title = " Off"
        statusLine?.title = reason
        NSLog("Global stopped: %@", reason)
    }

    func screenConfigurationChanged() {
        // Menu/Dock visibility also posts screen-parameter notifications.
        // Only stop for a real change to the captured display or its full frame.
        guard let id = capturedDisplayID, let overlay else { return }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        if screen == nil || screen!.frame != overlay.frame {
            frameIsCurrent = false
            if let screen {
                overlay.setFrame(screen.frame, display: false)
                let oldStream = stream
                stream = nil
                if let oldStream { Task { try? await oldStream.stopCapture() } }
            }
            suspend(reason: "Built-in display changed · Waiting to restore the live effect")
        }
    }

    private func update() {
        guard sleepReasons.isEmpty else { return }
        guard let renderer, let overlay else { return }
        let now = Monotonic.now
        if now - model.sensor.lastSuccessfulUpdate > 2 {
            suspend(reason: "Waiting for hinge data before resuming")
            return
        }
        if !receivedFrame && now - startedAt > 8 {
            if recoveryFailures < 3 {
                recoveryFailures += 1
                suspend(reason: "Waiting for a desktop frame after wake · Reconnecting")
            } else {
                stop(reason: "Desktop capture timed out and the overlay was removed · Re-enable it from the menu bar or Settings")
            }
            return
        }
        // The effect shows only while the lid moves: it turns off after 0.2 s
        // of stillness, or at once when the pointer is used (see EffectGate).
        let pointerUsed = pointerActivity.update(location: NSEvent.mouseLocation,
                                                 buttonsDown: NSEvent.pressedMouseButtons != 0,
                                                 secondsSinceInput: Self.secondsSinceClickOrScroll())
        let frameReady = frameIsCurrent && renderer.readyForDisplay
        let effectAllowed = effectGate.update(pointerUsed: pointerUsed, lidAngle: model.sensor.angle,
                                              frameReady: frameReady, now: now)
        // A static desktop may legitimately produce no new complete frames.
        // Keep the last valid texture; explicit stream errors still stop immediately.
        let remaining = effectGate.previewActive(at: now)
            ? 0.35 : max(0, 1 - model.sensor.angle / model.openAngle)
        // Hysteresis prevents overlay flicker near the calibrated endpoint.
        if remaining > 0.008 { requestedVisible = true }
        if remaining == 0 && renderer.settled { requestedVisible = false }
        if requestedVisible && effectAllowed && frameReady {
            renderer.setLiveAngle(remaining * 80)
            showOverlay(overlay, renderer: renderer)
        } else {
            // The 0.2 s gate is the complete cutoff. Remove the captured
            // texture with the rest of the effect instead of leaving a flat
            // copy of the desktop on screen. Natural stops fade; pointer use
            // and invalid frames remain immediate safety cutoffs.
            if overlay.isVisible {
                hideOverlay(overlay, animated: !pointerUsed && frameReady)
            }
            renderer.setLiveAngle(0)
        }
        setCaptureRate(fast: overlay.isVisible)
        statusTick += 1
        if statusTick % 30 == 0 {
            let state = overlay.isVisible ? "Effect Active"
                : (requestedVisible && !effectAllowed ? "Real Desktop · Move the Display to Show the Effect" : "Real Desktop")
            statusItem.button?.title = " \(Int(model.sensor.angle))°"
            statusLine.title = "\(state) · \(frameCount) Frames Captured · Fully Open at \(Int(model.openAngle))°"
            if statusTick % 120 == 0 { NSLog("%@", statusLine.title) }
        }
    }

    /// Put the panel on screen while fully transparent, render its current
    /// desktop frame, then reveal it. This avoids a one-frame black flash when
    /// AppKit first gives the Metal view a drawable.
    private func showOverlay(_ overlay: NSWindow, renderer: GlassMetalView) {
        if overlay.isVisible {
            guard overlayIsHiding else { return }
            overlayVisibilityGeneration += 1
            overlayIsHiding = false
            fade(overlay, to: 1)
            return
        }
        overlayVisibilityGeneration += 1
        let token = overlayVisibilityGeneration
        overlay.alphaValue = 0
        overlay.orderFrontRegardless()
        guard renderer.prepareToShow(completion: { [weak self, weak overlay] in
            guard let self, let overlay, self.overlay === overlay,
                  self.overlayVisibilityGeneration == token, overlay.isVisible else { return }
            self.fade(overlay, to: 1)
        }) else {
            overlay.orderOut(nil)
            overlay.alphaValue = 1
            return
        }
    }

    /// A short crossfade hides the final sub-pixel/color difference between the
    /// captured frame and the real desktop. Pointer activity remains immediate
    /// so the visual pointer and click target can never diverge.
    private func hideOverlay(_ overlay: NSWindow, animated: Bool) {
        guard !overlayIsHiding else { return }
        overlayVisibilityGeneration += 1
        let token = overlayVisibilityGeneration
        guard animated else {
            overlay.orderOut(nil)
            overlay.alphaValue = 1
            return
        }
        overlayIsHiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.overlayFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().alphaValue = 0
        } completionHandler: { [weak self, weak overlay] in
            Task { @MainActor in
                guard let self, let overlay, self.overlay === overlay,
                      self.overlayVisibilityGeneration == token else { return }
                overlay.orderOut(nil)
                overlay.alphaValue = 1
                self.overlayIsHiding = false
            }
        }
    }

    private func fade(_ overlay: NSWindow, to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.overlayFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().alphaValue = alpha
        }
    }

    private func cancelOverlayTransition() {
        overlayVisibilityGeneration += 1
        overlayIsHiding = false
        overlay?.alphaValue = 1
    }

    private static let overlayFadeDuration: TimeInterval = 0.15

    /// Full frame rate only while the effect is on screen. Otherwise a low rate
    /// still keeps a recent frame ready for the next lid movement.
    private func setCaptureRate(fast: Bool) {
        guard fast != captureIsFast, !captureRateChanging, let stream, let captureConfig else { return }
        captureIsFast = fast
        captureRateChanging = true
        captureConfig.minimumFrameInterval = CMTime(value: 1,
            timescale: fast ? Self.activeCaptureFPS : Self.idleCaptureFPS)
        let token = generation
        Task { @MainActor in
            try? await stream.updateConfiguration(captureConfig)
            if token == generation { captureRateChanging = false }
        }
    }

    private static let activeCaptureFPS: Int32 = 30
    private static let idleCaptureFPS: Int32 = 5

    /// Seconds since the last click or scroll anywhere: read-only timing from
    /// the window server. No event monitor, no event contents, no permission.
    private static func secondsSinceClickOrScroll() -> TimeInterval {
        [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard self.stream === stream, type == .screen, sampleBuffer.isValid else { return }
        guard sleepReasons.isEmpty else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        renderer?.receive(buffer)
        recoveryFailures = 0
        receivedFrame = true
        frameIsCurrent = true
        frameCount += 1
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let userStopped = CaptureSafety.isUserStop(error)
        Task { @MainActor in
            guard self.stream === stream else { return }
            self.stream = nil
            if userStopped {
                // Stopped from the system's screen-sharing control: that is the
                // user's decision, so never restart capture on our own.
                stop(reason: "Screen Recording was stopped in macOS · Re-enable it manually to continue")
                return
            }
            if recoveryFailures < 3 {
                recoveryFailures += 1
                suspend(reason: "Capture interrupted · Waiting to recover: \(error.localizedDescription)")
            } else {
                stop(reason: "Capture recovery failed · Re-enable it manually: \(error.localizedDescription)")
            }
        }
    }

    private func registerKeys() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // The handler is never removed, so it owns a strong reference and its
        // pointer can never dangle.
        let pointer = Unmanaged.passRetained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let controller = Unmanaged<GlobalDesktopController>.fromOpaque(pointer).takeUnretainedValue()
            switch id.id {
            case 1: controller.showSetup()
            case 2: controller.toggle()
            case 3: controller.calibrate()
            default: break
            }
            return noErr
        }, 1, &event, pointer, &eventHandler)
        // Registered for the app's lifetime; start() refuses to run without it.
        emergencyHotKey = registerHotKey(id: 1, code: UInt32(kVK_Escape))
    }

    private func setSessionHotKeys(enabled: Bool) {
        if enabled {
            guard sessionHotKeys.isEmpty else { return }
            for (id, code) in [(UInt32(2), UInt32(kVK_ANSI_G)), (3, UInt32(kVK_ANSI_K))] {
                if let ref = registerHotKey(id: id, code: code) { sessionHotKeys.append(ref) }
            }
        } else {
            sessionHotKeys.forEach { UnregisterEventHotKey($0) }
            sessionHotKeys.removeAll()
        }
    }

    private func registerHotKey(id: UInt32, code: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(code, UInt32(cmdKey | shiftKey),
            EventHotKeyID(signature: 0x48474C53, id: id), GetApplicationEventTarget(), 0, &ref)
        return result == noErr ? ref : nil
    }

    enum GlobalError: LocalizedError {
        case noInternalDisplay, cannotExcludeSelf, noGPU
        var errorDescription: String? {
            switch self {
            case .noInternalDisplay: return "Built-in display not found"
            case .cannotExcludeSelf: return "Could not exclude this app's windows; capture was cancelled to prevent recursion"
            case .noGPU: return "Metal is unavailable"
            }
        }
    }
}
