import Foundation
import Security

/// Development-build migration, not an authorization bypass. Never reset other apps.
enum ScreenCapturePermissionPreparation {
    static let bundleID = "app.hingescape.mac"
    static let markerKey = "screenCapture.preparedCodeIdentity.v1"

    static func needsReset(identity: String, defaults: UserDefaults) -> Bool {
        defaults.string(forKey: markerKey) != identity
    }

    static func recordSuccess(identity: String, defaults: UserDefaults) {
        defaults.set(identity, forKey: markerKey)
    }

    /// Arguments that reset only `client`'s grant. Nil for an empty client:
    /// `tccutil reset ScreenCapture` without one resets every app on the Mac.
    static func resetArguments(for client: String) -> [String]? {
        guard !client.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return ["reset", "ScreenCapture", client]
    }

    static func codeIdentity() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let values = information as? [String: Any],
              let hash = values[kSecCodeInfoUnique as String] as? Data,
              !hash.isEmpty else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func prepare() async -> String? {
        guard Bundle.main.bundleIdentifier == bundleID, let identity = codeIdentity(),
              let arguments = resetArguments(for: bundleID) else {
            return "The app signature could not be verified, so permission was not reset automatically. Reset Screen Recording permission for this app manually."
        }
        guard needsReset(identity: identity, defaults: .standard) else { return nil }
        let succeeded: Bool = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            do { try process.run() }
            catch { continuation.resume(returning: false) }
        }
        guard succeeded else {
            return "Permission reset failed and capture was not requested. Reopen the app or reset its Screen Recording permission manually."
        }
        recordSuccess(identity: identity, defaults: .standard)
        return "Permission was reset for this build. Allow Screen Recording again when enabling Live Desktop."
    }
}
