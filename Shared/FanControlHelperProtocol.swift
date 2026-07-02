import Foundation

// This file is compiled into *both* the GUI app (XPC client) and the privileged
// helper daemon (XPC server). NSXPC matches interfaces by selector at runtime,
// so sharing the exact same declaration keeps the two sides in lockstep.

/// Well-known names shared between the app and the privileged helper daemon.
public enum HelperConstants {
    /// Mach service the daemon vends and the app connects to. Must match the
    /// `MachServices` key in the launchd plist and the `machServiceName` used by
    /// `NSXPCConnection`.
    public static let machServiceName = "com.pair.FanControl.helper"

    /// Launchd plist filename under `Contents/Library/LaunchDaemons/`, passed to
    /// `SMAppService.daemon(plistName:)`.
    public static let daemonPlistName = "com.pair.FanControl.helper.plist"

    /// The GUI app's bundle identifier. The daemon requires connecting clients to
    /// carry this identifier (and our Team ID) before it will serve any request.
    public static let appBundleIdentifier = "com.pair.FanControl"
}

/// XPC interface the privileged helper exposes. Deliberately tiny: it offers only
/// the operations that actually require root — SMC *writes*. Sensor/state *reads*
/// don't need privilege and stay in the unprivileged app process
/// (`SystemStatusReader`), which keeps the root attack surface minimal.
@objc public protocol FanControlHelperProtocol {
    /// - Parameters:
    ///   - fanId: zero-based fan index.
    ///   - mode: `0` = automatic (macOS-managed), `1` = manual/forced.
    ///   - speed: target RPM, only used when `mode == 1`.
    ///   - reply: `(success, message)`.
    func setFan(fanId: Int, mode: Int, speed: Int, withReply reply: @escaping (Bool, String) -> Void)

    /// Return every fan to macOS automatic control.
    func resetAll(withReply reply: @escaping (Bool, String) -> Void)

    /// Liveness/handshake check used to confirm the daemon is reachable and the
    /// client passed code-signature validation.
    func ping(withReply reply: @escaping (String) -> Void)
}
