import Foundation
import ServiceManagement

// Client-side counterpart to the privileged helper daemon. Owns two things:
//   1. Installation/registration of the daemon via SMAppService (macOS 13+).
//   2. The XPC connection used to issue the (root-requiring) SMC writes.
//
// This replaces the old setuid-root `smc-helper` CLI that was invoked with
// `Process`. There is no longer a persistent root-capable binary anyone can run,
// no `chmod +s`, and nothing that mutates (and thereby invalidates) the app's
// code signature.
final class PrivilegedHelperClient {
    static let shared = PrivilegedHelperClient()

    private var connection: NSXPCConnection?
    private let lock = NSLock()

    private var service: SMAppService {
        SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
    }

    // MARK: - Registration / status

    var status: SMAppService.Status { service.status }

    /// True once the daemon is registered *and* approved by the user.
    var isEnabled: Bool { service.status == .enabled }

    /// Register the daemon with launchd. Returns `nil` on success, or a
    /// human-readable error. Even on success the user may still need to approve
    /// the item under System Settings ▸ General ▸ Login Items (status becomes
    /// `.requiresApproval` until they do).
    func register() -> String? {
        do {
            try service.register()
            return nil
        } catch {
            return (error as NSError).localizedDescription
        }
    }

    /// Remove the daemon (used if the user ever wants to fully uninstall it).
    func unregister(completion: @escaping (String?) -> Void) {
        service.unregister { error in
            completion(error.map { ($0 as NSError).localizedDescription })
        }
    }

    /// Deep-link the user to the Login Items pane so they can approve the daemon.
    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - XPC connection

    private func currentConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }

        if let connection { return connection }

        let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: FanControlHelperProtocol.self)
        let clear: () -> Void = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.connection = nil
            self.lock.unlock()
        }
        conn.invalidationHandler = clear
        conn.interruptionHandler = clear
        conn.resume()
        connection = conn
        return conn
    }

    private func proxy(_ errorHandler: @escaping (Error) -> Void) -> FanControlHelperProtocol? {
        currentConnection().remoteObjectProxyWithErrorHandler(errorHandler) as? FanControlHelperProtocol
    }

    // MARK: - Operations

    func setFan(fanId: Int, mode: Int, speed: Int, completion: ((Bool, String) -> Void)? = nil) {
        let helper = proxy { completion?(false, $0.localizedDescription) }
        helper?.setFan(fanId: fanId, mode: mode, speed: speed) { ok, msg in completion?(ok, msg) }
    }

    func resetAll(completion: ((Bool, String) -> Void)? = nil) {
        let helper = proxy { completion?(false, $0.localizedDescription) }
        helper?.resetAll { ok, msg in completion?(ok, msg) }
    }

    /// Synchronous reset for use on app termination, where async work would be
    /// killed before it completes. Bounded by a timeout so quitting never hangs
    /// on a wedged connection.
    @discardableResult
    func resetAllBlocking(timeout: TimeInterval = 2.0) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        var result = false
        let helper = proxy { _ in sem.signal() }
        helper?.resetAll { ok, _ in
            result = ok
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + timeout)
        return result
    }
}
