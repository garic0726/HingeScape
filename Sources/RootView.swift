import SwiftUI
import AppKit

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            switch model.page {
            case .setup:
                SetupView(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            case .test:
                TestView(model: model, sensor: model.sensor)
                    .transition(.opacity)
            }
        }
        .background(Color.black)
    }
}

private struct SetupView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var sensor: LidAngleSensor

    init(model: AppModel) {
        self.model = model
        self.sensor = model.sensor
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.055, green: 0.065, blue: 0.09), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.indigo.opacity(0.22))
                    .frame(width: 680, height: 680)
                    .blur(radius: 120)
                    .offset(x: -proxy.size.width * 0.35, y: -proxy.size.height * 0.35)

                HStack(spacing: 70) {
                    setupCopy
                        .frame(maxWidth: 500, alignment: .leading)

                    screenshotPreview
                        .frame(width: min(460, proxy.size.width * 0.40))
                }
                .padding(.horizontal, 74)
                .padding(.vertical, 64)
            }
            .ignoresSafeArea()
        }
    }

    private var setupCopy: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled")
                    .symbolRenderingMode(.hierarchical)
                Text("HINGESCAPE")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.4)
            }
            .foregroundStyle(.white.opacity(0.55))

            Text("Let your interface unfold\nwith the display.")
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .tracking(-2.2)
                .padding(.top, 24)

            Text("Import a desktop screenshot to configure the floating glass effect. Set your MacBook's fully open position by opening the display to your normal viewing angle and saving it as the endpoint. The effect transitions from 0° to that position.")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.62))
                .lineSpacing(5)
                .frame(maxWidth: 450, alignment: .leading)
                .padding(.top, 18)

            HStack(spacing: 9) {
                Circle()
                    .fill(sensor.isAvailable ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .shadow(color: sensor.isAvailable ? .green.opacity(0.8) : .orange.opacity(0.8), radius: 5)
                Text(sensor.statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.top, 24)

            HStack(spacing: 12) {
                Button(action: model.importScreenshot) {
                    Label(model.desktopImage == nil ? "Import Desktop Screenshot" : "Replace Screenshot", systemImage: "photo.badge.plus")
                        .frame(minWidth: 124)
                }
                .buttonStyle(GlassButtonStyle(prominent: false))

                Button(action: model.startTest) {
                    HStack(spacing: 8) {
                        Text("Import a Screenshot to Continue")
                        Image(systemName: "arrow.right")
                    }
                    .frame(minWidth: 108)
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
                .disabled(model.desktopImage == nil)
                .opacity(model.desktopImage == nil ? 0.42 : 1)
            }
            .padding(.top, 34)

            Text("Screenshot shortcut: ⇧⌘3")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.34))
                .padding(.top, 14)
            Button("Enable Live Desktop Effect") { model.startGlobal?() }
                .buttonStyle(GlassButtonStyle(prominent: true))
                .disabled(model.globalRunning || model.permissionsPreparing)
                .padding(.top, 22)
            Text(model.globalStatus)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 8)
            Button("Preview for 8 Seconds (No Display Movement Needed)") { model.previewGlobal?() }
                .buttonStyle(.link)
                .padding(.top, 8)
            Text("⌘⇧Esc Emergency Stop · While running: ⌘⇧G Stop, ⌘⇧K Save Endpoint")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 6)
        }
    }

    private var screenshotPreview: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.045))

                if let image = model.desktopImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            VStack(spacing: 9) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 24))
                                Text("Glass Layer Preview")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(.white.opacity(0.24), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.32), radius: 28, y: 18)
                        .frame(width: 210, height: 126)
                } else {
                    VStack(spacing: 15) {
                        Image(systemName: "macbook")
                            .font(.system(size: 46, weight: .light))
                            .foregroundStyle(.white.opacity(0.33))
                        Text("Waiting for a Desktop Screenshot")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.44))
                    }
                }
            }
            .aspectRatio(1.42, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 40, y: 25)

            if !model.importedFileName.isEmpty {
                Label(model.importedFileName, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }
}

private struct TestView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var sensor: LidAngleSensor
    @State private var strength = 1.0
    @State private var frost = 0.09
    private let distance = 2.4

    private var angle: Double {
        model.useSensor && sensor.isAvailable ? sensor.angle : model.simulatedAngle
    }

    var body: some View {
        ZStack {
            if let image = model.desktopImage {
                GlassSurface(image: image, tilt: model.showOriginal ? 0 : 80 * (1 - pow(min(model.openAngle, max(0, angle)) / model.openAngle, 1 / strength)),
                             frost: frost, distance: distance)
                    .ignoresSafeArea()
            }
            if !model.controlsHidden {
                VStack {
                    HStack {
                        Button("Back", action: model.returnToSetup)
                        Spacer()
                        Text("HINGESCAPE · EFFECT SETTINGS").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button("Quit App") { NSApp.terminate(nil) }
                        Button("Hide / Show · ⌘H") { model.controlsHidden.toggle() }
                    }
                    .buttonStyle(FloatingControlStyle())
                    .padding(.horizontal, 22)
                    .padding(.top, 46)
                    Spacer()
                    VStack(spacing: 12) {
                        HStack {
                            Circle().fill(model.useSensor && sensor.isAvailable ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text("\(Int(angle.rounded()))°").monospacedDigit()
                            Text("0–\(Int(model.openAngle.rounded()))°").foregroundStyle(.secondary)
                            Spacer()
                            Toggle("Original Comparison ⌘B", isOn: $model.showOriginal).toggleStyle(.checkbox)
                            Button("Save Fully Open Angle ⌘K") { model.saveOpenAngle() }
                        }
                        HStack {
                            if sensor.isAvailable {
                                Toggle("Live Hinge", isOn: $model.useSensor).toggleStyle(.switch).controlSize(.small)
                            }
                            Spacer()
                            Text(model.calibrationMessage.isEmpty ? "Open the display to a comfortable angle, then save the endpoint" : model.calibrationMessage).foregroundStyle(.secondary)
                        }
                        if !model.useSensor || !sensor.isAvailable {
                            HStack {
                                Text("Simulated Angle").frame(width: 100, alignment: .leading)
                                Slider(value: $model.simulatedAngle, in: 0...180)
                            }
                        }
                        HStack {
                            Text("Depth").frame(width: 64, alignment: .leading)
                            Slider(value: $strength, in: 0.5...2)
                            Text(String(format: "%.1f×", strength)).frame(width: 35)
                            Text("Frost")
                            Slider(value: $frost, in: 0...0.18).frame(width: 100)
                        }
                        Text("⌘H Hide / Show · Esc Show Controls · ⌘K Save Endpoint · ⌘Q Quit")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                    .padding(16)
                    .frame(width: 610)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.2), lineWidth: 0.7) }
                    .padding(.bottom, 20)
                }
            }
        }
        .background(.black)
        .focusable()
        .focusEffectDisabled()
    }
}

private struct GlassButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, 19)
            .frame(height: 44)
            .background(
                prominent ? AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.78 : 0.96)) : AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
            .overlay {
                if !prominent {
                    Capsule().stroke(.white.opacity(0.18), lineWidth: 0.7)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct FloatingControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.18), lineWidth: 0.7) }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 7)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
