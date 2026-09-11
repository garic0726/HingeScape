import Foundation
import IOKit.hid

/// Reads the undocumented lid-angle HID device used by newer MacBooks.
/// This is intentionally kept separate from the visual layer so a public API
/// can replace it later without changing the prototype's interaction model.
@MainActor
final class LidAngleSensor: ObservableObject {
    @Published private(set) var angle = 105.0
    /// Monotonic time (see `Monotonic`) of the last good reading.
    private(set) var lastSuccessfulUpdate = -TimeInterval.infinity
    @Published private(set) var isAvailable = false
    @Published private(set) var statusText = "Looking for the hinge sensor…"

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: Timer?
    private var report = [UInt8](repeating: 0, count: 8)
    // Clients that need live angles (the test page, live mode). With none,
    // the sensor is left idle instead of being read 30 times a second.
    private var fastPollingClients = Set<String>()
    private let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)

    init() {
        discoverDevice()
    }

    deinit {
        timer?.invalidate()
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    func start() {
        guard !isAvailable else { return }
        guard let device else {
            isAvailable = false
            statusText = "This device does not support the hinge sensor"
            return
        }

        guard IOHIDDeviceOpen(device, noOptions) == kIOReturnSuccess else {
            isAvailable = false
            statusText = "Could not open the sensor · Manual simulation is available"
            return
        }

        isAvailable = true
        statusText = "This device supports the hinge sensor"
        poll()
        updatePolling()
    }

    func setFastPolling(_ active: Bool, for client: String) {
        if active { fastPollingClients.insert(client) } else { fastPollingClients.remove(client) }
        updatePolling()
    }

    /// One immediate reading, e.g. before saving the open angle while idle.
    func refresh() {
        poll()
    }

    private func updatePolling() {
        let wanted = isAvailable && !fastPollingClients.isEmpty
        if wanted, timer == nil {
            poll()
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else if !wanted, let timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    private func discoverDevice() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, noOptions)
        self.manager = manager

        guard IOHIDManagerOpen(manager, noOptions) == kIOReturnSuccess else {
            statusText = "HID service unavailable · Manual simulation is available"
            return
        }

        // Apple devices only: another vendor's orientation sensor would feed
        // unrelated values into the overlay.
        let matchStrategies: [[String: Any]] = [
            [
                kIOHIDVendorIDKey as String: 0x05AC,
                kIOHIDProductIDKey as String: 0x8104,
                kIOHIDDeviceUsagePageKey as String: 0x0020,
                kIOHIDDeviceUsageKey as String: 0x008A
            ],
            [
                kIOHIDVendorIDKey as String: 0x05AC,
                kIOHIDDeviceUsagePageKey as String: 0x0020,
                kIOHIDDeviceUsageKey as String: 0x008A
            ]
        ]

        for matching in matchStrategies {
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
            guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
                continue
            }
            for candidate in devices where canRead(candidate) {
                device = candidate
                statusText = "This device supports the hinge sensor"
                return
            }
        }

        statusText = "This device does not support the hinge sensor"
    }

    private func canRead(_ candidate: IOHIDDevice) -> Bool {
        guard IOHIDDeviceOpen(candidate, noOptions) == kIOReturnSuccess else { return false }
        defer { IOHIDDeviceClose(candidate, noOptions) }

        var probe = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(probe.count)
        let result = IOHIDDeviceGetReport(
            candidate,
            kIOHIDReportTypeFeature,
            1,
            &probe,
            &length
        )
        return result == kIOReturnSuccess && length >= 3
    }

    private func poll() {
        guard let device else { return }
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            1,
            &report,
            &length
        )

        guard result == kIOReturnSuccess, length >= 3 else { return }
        let rawValue = UInt16(report[2]) << 8 | UInt16(report[1])
        var measured = Double(rawValue)
        // A small number of implementations expose hundredths of a degree.
        if measured > 360 { measured /= 100.0 }
        guard measured.isFinite, measured >= 0, measured <= 180 else { return }

        lastSuccessfulUpdate = Monotonic.now
        // Publish only real changes so a still lid doesn't redraw the UI.
        if angle != measured { angle = measured }
    }
}
