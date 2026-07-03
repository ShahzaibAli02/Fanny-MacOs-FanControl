import SwiftUI
import AppKit
import UserNotifications
import IOKit.ps
import ServiceManagement

// MARK: - View Model
class FanViewModel: ObservableObject {
    @Published var fans: [FanJSON] = []
    @Published var cpuTemp: Double? = nil
    @Published var gpuTemp: Double? = nil
    @Published var batteryTemp: Double? = nil
    @Published var tempHistory: [TempRecord] = []
    
    private var lastHistoryRecordTime: Date? = nil
    
    @Published var isAuthorized: Bool = false
    @Published var linkedFans: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isPollingActive: Bool = false
    @Published var isOnACPower: Bool = true

    var maxFanSpeed: Int? {
        fans.map { $0.currentSpeed }.max()
    }
    
    @Published var rules: [TriggerRule] = [] {
        didSet {
            saveRules()
        }
    }
    @Published var isRulesEngineEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isRulesEngineEnabled, forKey: "isRulesEngineEnabled")
            if !isRulesEngineEnabled && wasRuleApplied {
                resetAll()
                wasRuleApplied = false
                lastSetSpeedPercent = nil
            }
        }
    }
    private var wasRuleApplied = false
    private var lastSetSpeedPercent: Double? = nil
    
    private var timer: Timer? = nil

    private let helper = PrivilegedHelperClient.shared

    init() {
        checkAuthorization()
        loadRules()
        loadHistory()
        updatePowerSource()
        startPolling()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func checkAuthorization() {
        let enabled = helper.isEnabled
        DispatchQueue.main.async {
            self.isAuthorized = enabled
        }
    }

    /// Registers the privileged helper daemon with launchd via SMAppService and
    /// steers the user through approval if macOS requires it. Replaces the old
    /// setuid (`chown root:wheel` + `chmod +s`) flow.
    func authorize() {
        if let err = helper.register() {
            self.errorMessage = "Could not register the helper: \(err)"
            self.isAuthorized = false
            return
        }

        switch helper.status {
        case .enabled:
            self.errorMessage = nil
            self.isAuthorized = true
            self.updateStatus()
        case .requiresApproval:
            self.errorMessage = "Almost done — approve “Fan Control” under System Settings ▸ General ▸ Login Items to enable fan adjustments."
            self.isAuthorized = false
            helper.openApprovalSettings()
        case .notFound:
            self.errorMessage = "Helper daemon not found in the app bundle. Rebuild the app with build.sh."
            self.isAuthorized = false
        case .notRegistered:
            self.errorMessage = "Helper registration didn't take effect. Please try again."
            self.isAuthorized = false
        @unknown default:
            self.errorMessage = "Unexpected helper status."
            self.isAuthorized = false
        }
    }
    
    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        updateStatus()
    }
    
    private var statusCheckCounter = 0
    // helper.isEnabled queries SMAppService, which round-trips to
    // servicemanagementd. That status essentially never changes outside of a
    // deliberate System Settings action, so it doesn't need re-checking on
    // every 1.5s poll — every 20th cycle (~30s) is plenty responsive.
    private let authCheckInterval = 20

    func updateStatus() {
        // SMC reads don't require root, so query in-process rather than going
        // through the privileged helper on every poll cycle.
        let shouldCheckAuth = statusCheckCounter % authCheckInterval == 0
        statusCheckCounter += 1
        DispatchQueue.global(qos: .default).async {
            let decoded = SystemStatusReader.read()
            // Keep authorization in sync: this picks up the user approving (or
            // later removing) the daemon in System Settings without a relaunch.
            let enabled = shouldCheckAuth ? self.helper.isEnabled : nil
            DispatchQueue.main.async {
                if let enabled {
                    self.isAuthorized = enabled
                }
                self.fans = decoded.fans
                self.cpuTemp = decoded.cpuTemp
                self.gpuTemp = decoded.gpuTemp
                self.batteryTemp = decoded.batteryTemp
                self.isPollingActive = true
                self.updatePowerSource()
                self.evaluateRules()
                self.recordHistoryIfNeeded()
            }
        }
    }

    private func updatePowerSource() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, firstSource)?.takeUnretainedValue() as? [String: AnyObject],
              let state = description[kIOPSPowerSourceStateKey] as? String
        else {
            // Desktop Macs (or anything without a reported power source) count as AC.
            isOnACPower = true
            return
        }
        isOnACPower = (state == kIOPSACPowerValue)
    }
    
    func setFanMode(fanId: Int, mode: Int, speed: Int? = nil) {
        helper.setFan(fanId: fanId, mode: mode, speed: speed ?? 0) { [weak self] ok, msg in
            DispatchQueue.main.async {
                self?.errorMessage = ok ? nil : msg
                self?.updateStatus()
            }
        }
    }
    
    func changeFanMode(fanId: Int, mode: Int) {
        if linkedFans {
            for fan in fans {
                let targetSpeed = mode == 1 ? fan.minSpeed : nil
                setFanMode(fanId: fan.id, mode: mode, speed: targetSpeed)
            }
        } else {
            if let fan = fans.first(where: { $0.id == fanId }) {
                let targetSpeed = mode == 1 ? fan.minSpeed : nil
                setFanMode(fanId: fanId, mode: mode, speed: targetSpeed)
            }
        }
    }
    
    func changeFanSpeed(fanId: Int, speed: Int) {
        if linkedFans {
            for fan in fans {
                // Ensure we don't exceed the bounds of each specific fan
                let boundedSpeed = min(max(speed, fan.minSpeed), fan.maxSpeed)
                setFanMode(fanId: fan.id, mode: 1, speed: boundedSpeed)
            }
        } else {
            setFanMode(fanId: fanId, mode: 1, speed: speed)
        }
    }
    
    func resetAll() {
        helper.resetAll { [weak self] ok, msg in
            DispatchQueue.main.async {
                self?.errorMessage = ok ? nil : msg
                self?.updateStatus()
            }
        }
    }

    /// Synchronous reset used on app termination, where async work would be
    /// killed before it completes. Blocks the quit briefly so fans don't get
    /// left pinned at an override speed after the app exits.
    @discardableResult
    func resetAllBlocking() -> Bool {
        guard isAuthorized else { return false }
        return helper.resetAllBlocking()
    }

    func setAllToPercentage(_ pct: Double) {
        for fan in fans {
            let range = Double(fan.maxSpeed - fan.minSpeed)
            let targetSpeed = Double(fan.minSpeed) + range * pct
            setFanMode(fanId: fan.id, mode: 1, speed: Int(targetSpeed))
        }
    }
    
    func saveRules() {
        if let encoded = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(encoded, forKey: "triggerRules")
        }
    }
    
    func loadRules() {
        isRulesEngineEnabled = UserDefaults.standard.bool(forKey: "isRulesEngineEnabled")
        if let data = UserDefaults.standard.data(forKey: "triggerRules"),
           let decoded = try? JSONDecoder().decode([TriggerRule].self, from: data) {
            self.rules = decoded
        } else {
            self.rules = [
                TriggerRule(isEnabled: false, sensor: .cpu, thresholdTemp: 75.0, targetSpeedPercent: 80.0),
                TriggerRule(isEnabled: false, sensor: .battery, thresholdTemp: 40.0, targetSpeedPercent: 60.0)
            ]
        }
    }
    
    func evaluateRules() {
        guard isRulesEngineEnabled else { return }

        var maxTargetPercent: Double? = nil
        var winningSensor: TriggerRule.SensorType? = nil

        for rule in rules where rule.isEnabled {
            guard let currentTemp = getTempFor(sensor: rule.sensor) else { continue }

            var candidatePercent: Double? = nil

            if rule.ruleType == .threshold {
                if currentTemp >= rule.thresholdTemp {
                    candidatePercent = rule.targetSpeedPercent
                }
            } else if rule.ruleType == .curve {
                if currentTemp >= rule.minTemp {
                    let range = rule.maxTemp - rule.minTemp
                    let tempDiff = currentTemp - rule.minTemp
                    let speedDiff = rule.maxSpeedPercent - rule.minSpeedPercent

                    var calculatedPercent = rule.minSpeedPercent
                    if range > 0 {
                        let ratio = min(max(tempDiff / range, 0.0), 1.0)
                        calculatedPercent = rule.minSpeedPercent + ratio * speedDiff
                    }
                    candidatePercent = calculatedPercent
                }
            }

            guard var candidate = candidatePercent else { continue }
            // Gentler on battery: scale down rule-driven speeds to conserve
            // charge, unless the rule opts out (e.g. an emergency thermal rule).
            if !isOnACPower && rule.reduceOnBattery {
                candidate *= 0.75
            }

            if maxTargetPercent == nil || candidate > maxTargetPercent! {
                maxTargetPercent = candidate
                winningSensor = rule.sensor
            }
        }

        if let targetPercent = maxTargetPercent {
            let speedFraction = targetPercent / 100.0
            if !wasRuleApplied || lastSetSpeedPercent != targetPercent {
                setAllToPercentage(speedFraction)
                if let sensor = winningSensor {
                    notifyRuleTriggered(sensorName: sensor.rawValue, percent: targetPercent)
                }
                lastSetSpeedPercent = targetPercent
                wasRuleApplied = true
            }
        } else {
            if wasRuleApplied {
                resetAll()
                notifyRulesDisengaged()
                wasRuleApplied = false
                lastSetSpeedPercent = nil
            }
        }
    }

    private func notifyRuleTriggered(sensorName: String, percent: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Fan Control"
        content.body = "\(sensorName) rule activated: fans → \(Int(percent.rounded()))%"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func notifyRulesDisengaged() {
        let content = UNMutableNotificationContent()
        content.title = "Fan Control"
        content.body = "Temperatures back to normal — fans returned to automatic control."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func getTempFor(sensor: TriggerRule.SensorType) -> Double? {
        switch sensor {
        case .cpu: return cpuTemp
        case .gpu: return gpuTemp
        case .battery: return batteryTemp
        }
    }
    
    // MARK: - Temperature History Management
    private func recordHistoryIfNeeded() {
        let now = Date()
        
        // Ensure we have at least one valid reading
        guard cpuTemp != nil || gpuTemp != nil || batteryTemp != nil else { return }
        
        if let lastTime = lastHistoryRecordTime {
            // Only record every 30 seconds to avoid bloating
            guard now.timeIntervalSince(lastTime) >= 30.0 else { return }
        }
        
        let record = TempRecord(timestamp: now, cpu: cpuTemp, gpu: gpuTemp, battery: batteryTemp)
        tempHistory.append(record)
        lastHistoryRecordTime = now
        
        pruneHistory()
        saveHistory()
    }
    
    private func pruneHistory() {
        let cutoff = Date().addingTimeInterval(-12 * 3600) // 12 hours ago
        tempHistory.removeAll { $0.timestamp < cutoff }
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(tempHistory) {
            UserDefaults.standard.set(encoded, forKey: "tempHistory")
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "tempHistory"),
           let decoded = try? JSONDecoder().decode([TempRecord].self, from: data) {
            self.tempHistory = decoded
            self.lastHistoryRecordTime = decoded.last?.timestamp
        }
    }
}
