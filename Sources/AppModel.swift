import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    enum Page {
        case setup
        case test
    }

    @Published var page: Page = .setup
    @Published var desktopImage: NSImage?
    @Published var importedFileName = ""
    @Published var useSensor = true
    @Published var simulatedAngle = 105.0
    @Published var controlsHidden = false
    @Published var showOriginal = false
    @Published var calibrationMessage = ""
    @Published var openAngle = 120.0
    @Published var globalStatus = "Live Desktop requires Screen Recording permission"
    @Published var globalRunning = false
    @Published var permissionsPreparing = false
    var startGlobal: (() -> Void)?
    var previewGlobal: (() -> Void)?

    var currentAngle: Double { useSensor && sensor.isAvailable ? sensor.angle : simulatedAngle }

    func saveOpenAngle() {
        let value = currentAngle
        guard value.isFinite, value >= 1, value <= 180 else {
            calibrationMessage = "Open the display before saving the fully open angle"
            controlsHidden = false
            return
        }
        openAngle = value
        UserDefaults.standard.set(value, forKey: "calibratedOpenAngle")
        calibrationMessage = "Fully open angle saved"
    }

    let sensor = LidAngleSensor()

    init() {
        // Preserve calibration from the original MacBook Duo prototype.
        let saved = UserDefaults.standard.object(forKey: "calibratedOpenAngle") as? Double
            ?? UserDefaults(suiteName: "studio.prototype.HingeGlass")?.double(forKey: "calibratedOpenAngle") ?? 120
        if saved >= 1 && saved <= 180 { openAngle = saved }
        sensor.start()
    }

    func importScreenshot() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Desktop Screenshot"
        panel.message = "Choose a full desktop screenshot to use as the content beneath the glass layer."
        panel.prompt = "Import Screenshot"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]

        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url)
        else { return }

        desktopImage = image
        importedFileName = url.lastPathComponent
    }

    func startTest() {
        guard desktopImage != nil else { return }
        controlsHidden = false
        sensor.setFastPolling(true, for: "test")
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            page = .test
        }
    }

    func returnToSetup() {
        controlsHidden = false
        sensor.setFastPolling(false, for: "test")
        withAnimation(.easeInOut(duration: 0.3)) {
            page = .setup
        }
    }
}
