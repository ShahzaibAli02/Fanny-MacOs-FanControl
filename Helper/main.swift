//
//  main.swift
//  Fan Control privileged helper (XPC daemon)
//
//  This is no longer a setuid CLI. It is a launchd-managed root daemon, installed
//  by the app via SMAppService.daemon(...). It vends a single XPC service and does
//  only the SMC writes that require root. Every incoming connection must satisfy a
//  code-signing requirement (our Team ID + the app's bundle identifier) before any
//  request is served, so arbitrary local processes cannot drive the SMC through it.
//

import Foundation
import Security

// MARK: - Service implementation (runs as root)

final class HelperService: NSObject, FanControlHelperProtocol {
    func setFan(fanId: Int, mode: Int, speed: Int, withReply reply: @escaping (Bool, String) -> Void) {
        // The daemon never trusts caller input blindly, even after code-sign checks.
        guard fanId >= 0, fanId < 64 else {
            reply(false, "Invalid fan id \(fanId)")
            return
        }

        let smc = SMC.shared
        switch mode {
        case 0:
            let ok = smc.setFanMode(fanId, mode: .automatic)
            reply(ok, ok ? "Fan \(fanId) → automatic" : "Failed to set fan \(fanId) to automatic")
        case 1:
            guard speed >= 0, speed <= 100_000 else {
                reply(false, "Invalid speed \(speed)")
                return
            }
            guard smc.setFanMode(fanId, mode: .forced) else {
                reply(false, "Failed to set fan \(fanId) to manual")
                return
            }
            let ok = smc.setFanSpeed(fanId, speed: speed)
            reply(ok, ok ? "Fan \(fanId) → \(speed) RPM" : "Failed to set fan \(fanId) speed")
        default:
            reply(false, "Invalid mode \(mode); expected 0 (auto) or 1 (manual)")
        }
    }

    func resetAll(withReply reply: @escaping (Bool, String) -> Void) {
        let ok = SMC.shared.resetFanControl()
        reply(ok, ok ? "Reset all fans to automatic" : "Failed to reset fan control")
    }

    func ping(withReply reply: @escaping (String) -> Void) {
        reply("ok")
    }
}

// MARK: - Listener delegate (client authentication)

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard let requirement = Self.clientCodeSigningRequirement() else {
            // Ad-hoc / unsigned builds have no Team ID to pin against. Rather than
            // accept anyone as root, refuse. (SMAppService can't register an
            // unsigned daemon anyway, so this only bites bare local test runs.)
            NSLog("smc-helper: refusing connection — no Team ID on this build; sign with Developer ID.")
            return false
        }

        // macOS 13+: enforce that the peer satisfies the requirement. If it does
        // not, XPC invalidates the connection and no messages are delivered.
        newConnection.setCodeSigningRequirement(requirement)

        newConnection.exportedInterface = NSXPCInterface(with: FanControlHelperProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }

    /// Require the client to be Apple-signed, from *our* Team, and carrying the
    /// app's bundle identifier. Built from the daemon's *own* signature so there
    /// is no Team ID to hardcode or keep in sync across builds.
    static func clientCodeSigningRequirement() -> String? {
        guard let team = ownTeamIdentifier() else { return nil }
        return "anchor apple generic and identifier \"\(HelperConstants.appBundleIdentifier)\" "
             + "and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// This daemon's Apple Developer Team identifier, read from its own signature.
    static func ownTeamIdentifier() -> String? {
        var codeRef: SecCode?
        guard SecCodeCopySelf([], &codeRef) == errSecSuccess, let codeRef else { return nil }

        var staticRef: SecStaticCode?
        guard SecCodeCopyStaticCode(codeRef, [], &staticRef) == errSecSuccess, let staticRef else { return nil }

        var infoRef: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(staticRef, flags, &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else { return nil }

        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

// MARK: - Entry point

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
