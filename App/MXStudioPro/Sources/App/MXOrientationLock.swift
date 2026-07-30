import SwiftUI
import UIKit

/// Optional portrait lock while Studio is in record mode (Week 41).
///
/// GarageBand often forces landscape for instruments; MXStudio keeps Studio free-rotate
/// and offers an opt-in portrait lock so mic posture doesn’t flip chrome mid-take.
enum MXOrientationLock {
    static let preferenceKey = "mxstudio.lockRecordOrientation"

    /// Supported orientations when unlocked (matches Info.plist).
    static let unlockedMask: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight]

    /// Read from `UIApplicationDelegate` on the main thread.
    nonisolated(unsafe) private(set) static var supportedMask: UIInterfaceOrientationMask = unlockedMask

    @MainActor
    static var prefersPortraitWhileRecording: Bool {
        get { UserDefaults.standard.bool(forKey: preferenceKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferenceKey) }
    }

    /// Call when entering/leaving record mode — locks only if the user opted in.
    @MainActor
    static func applyForRecordMode(_ isRecordMode: Bool) {
        if isRecordMode, prefersPortraitWhileRecording {
            lockPortrait()
        } else {
            unlock()
        }
    }

    @MainActor
    static func lockPortrait() {
        setMask(.portrait, preferPortrait: true)
    }

    @MainActor
    static func unlock() {
        setMask(unlockedMask, preferPortrait: false)
    }

    @MainActor
    private static func setMask(_ mask: UIInterfaceOrientationMask, preferPortrait: Bool) {
        supportedMask = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let orientations: UIInterfaceOrientationMask = preferPortrait ? .portrait : mask
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
        scene.requestGeometryUpdate(prefs) { _ in }

        scene.windows.forEach { window in
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

/// Supplies the dynamic orientation mask for `MXOrientationLock`.
final class MXAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MXOrientationLock.supportedMask
    }
}
