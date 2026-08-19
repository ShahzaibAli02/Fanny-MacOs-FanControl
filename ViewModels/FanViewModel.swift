import SwiftUI
import AppKit
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
    @Published var isAutoStart: Bool = SMAppService.mainApp.status == .enabled
    
    @Published var rules: [TriggerRule] = [] {
        didSet {
            saveRules()
        }
    }
    @Published var isRulesEngineEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isRulesEngineEnabled, forKey: "isRulesEngineEnabled")
            if !isRulesEngineEnabled {
                if wasRuleApplied {
                    resetAll()
                }
                wasRuleApplied = false
                lastSetSpeedPercent = nil
                resetRuleResponse()
            }
        }
    }
    @Published var rampUpTimeConstant: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(rampUpTimeConstant, forKey: "rampUpTimeConstant")
        }
    }
    @Published var rampDownTimeConstant: Double = 10.0 {
        didSet {
            UserDefaults.standard.set(rampDownTimeConstant, forKey: "rampDownTimeConstant")
        }
    }
    private var wasRuleApplied = false
    private var lastSetSpeedPercent: Double? = nil
    private var filteredRuleTargetPercent: Double? = nil
    private var lastRuleEvaluationDate: Date? = nil

    private let emergencyBypassPercent = 90.0
    private let updateResolutionPercent = 1.0
    private let releaseToAutoPercent = 0.5
    
    private var timer: Timer? = nil
    private var isAppActive = true
    private var isStatusUpdateInProgress = false
    
    var helperPath: String {
        let bundleHelper = Bundle.main.bundlePath + "/Contents/MacOS/smc-helper"
        if FileManager.default.fileExists(atPath: bundleHelper) {
            return bundleHelper
        }
        return FileManager.default.currentDirectoryPath + "/smc-helper"
    }
    
    init() {
        checkAuthorization()
        loadRules()
        loadResponseSettings()
        loadHistory()
        startPolling()
    }
    
    func checkAuthorization() {
        let path = helperPath
        guard FileManager.default.fileExists(atPath: path) else {
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
            return
        }
        
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
            let ownerId = attributes[.ownerAccountID] as? Int ?? -1
            let posixPermissions = attributes[.posixPermissions] as? Int ?? 0
            let isSetuid = (posixPermissions & 0o4000) != 0
            
            DispatchQueue.main.async {
                self.isAuthorized = (ownerId == 0 && isSetuid)
            }
        } else {
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
        }
    }
    
    func authorize() {
        let path = helperPath
        guard FileManager.default.fileExists(atPath: path) else {
            self.errorMessage = "Helper tool 'smc-helper' not found. Please verify project compilation."
            return
        }
        
        let appleScriptSource = """
        do shell script "chown root:wheel '\(path)' && chmod +s '\(path)'" with administrator privileges
        """
        
        guard let appleScript = NSAppleScript(source: appleScriptSource) else {
            self.errorMessage = "Failed to compile authorization script."
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary? = nil
            appleScript.executeAndReturnError(&error)
            
            DispatchQueue.main.async {
                if let err = error {
                    let desc = err[NSAppleScript.errorMessage] as? String ?? "Authorization rejected or failed."
                    if desc.contains("Read-only file system") {
                        self.errorMessage = "Please move Fan Control to your Applications folder before authorizing. The helper tool cannot be configured on a read-only disk image."
                    } else {
                        self.errorMessage = desc
                    }
                    self.isAuthorized = false
                } else {
                    self.errorMessage = nil
                    self.isAuthorized = true
                    self.updateStatus()
                }
            }
        }
    }
    
    func startPolling() {
        timer?.invalidate()
        let interval = pollingInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        timer?.tolerance = interval * 0.2
        updateStatus()
    }

    func setAppActive(_ isActive: Bool) {
        guard isAppActive != isActive else { return }
        isAppActive = isActive
        startPolling()
    }

    private var pollingInterval: TimeInterval {
        if isAppActive {
            return 1.5
        }
        // Rules still run while the app is hidden, but a slightly slower background
        // cadence avoids repeatedly starting the privileged helper when it is idle.
        return isRulesEngineEnabled ? 3.0 : 6.0
    }
    
    func updateStatus() {
        let path = helperPath
        guard FileManager.default.fileExists(atPath: path), !isStatusUpdateInProgress else { return }
        isStatusUpdateInProgress = true
        
        DispatchQueue.global(qos: .default).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = ["get"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let decoded = try? JSONDecoder().decode(SystemStatusJSON.self, from: data) {
                    DispatchQueue.main.async {
                        self.fans = decoded.fans
                        self.cpuTemp = self.acceptTemperature(
                            decoded.cpuTemp,
                            previous: self.cpuTemp,
                            sensor: .cpu
                        )
                        self.gpuTemp = self.acceptTemperature(
                            decoded.gpuTemp,
                            previous: self.gpuTemp,
                            sensor: .gpu
                        )
                        self.batteryTemp = self.acceptTemperature(
                            decoded.batteryTemp,
                            previous: self.batteryTemp,
                            sensor: .battery
                        )
                        self.isPollingActive = true
                        self.evaluateRules()
                        self.recordHistoryIfNeeded()
                        self.isStatusUpdateInProgress = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isStatusUpdateInProgress = false
                    }
                }
            } catch {
                print("Status fetch failed: \(error)")
                DispatchQueue.main.async {
                    self.isStatusUpdateInProgress = false
                }
            }
        }
    }
    
    func setFanMode(fanId: Int, mode: Int, speed: Int? = nil) {
        let path = helperPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            
            var args = ["set", "\(fanId)", "\(mode)"]
            if mode == 1, let spd = speed {
                args.append("\(spd)")
            }
            task.arguments = args
            
            do {
                try task.run()
                task.waitUntilExit()
                DispatchQueue.main.async {
                    self.updateStatus()
                }
            } catch {
                print("Set fan failed: \(error)")
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
        let path = helperPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = ["reset"]
            
            do {
                try task.run()
                task.waitUntilExit()
                DispatchQueue.main.async {
                    self.updateStatus()
                }
            } catch {
                print("Reset failed: \(error)")
            }
        }
    }
    
    func setAllToPercentage(_ pct: Double) {
        let path = helperPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        
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

    private func loadResponseSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "rampUpTimeConstant") != nil {
            rampUpTimeConstant = defaults.double(forKey: "rampUpTimeConstant")
        }
        if defaults.object(forKey: "rampDownTimeConstant") != nil {
            rampDownTimeConstant = defaults.double(forKey: "rampDownTimeConstant")
        }
    }

    private func resetRuleResponse() {
        filteredRuleTargetPercent = nil
        lastRuleEvaluationDate = nil
    }

    private func filteredRuleTarget(toward desiredPercent: Double, now: Date) -> Double {
        defer { lastRuleEvaluationDate = now }

        guard let previous = filteredRuleTargetPercent,
              let previousDate = lastRuleEvaluationDate else {
            // Apply the first demand immediately; this is the conservative choice.
            filteredRuleTargetPercent = desiredPercent
            return desiredPercent
        }

        // Do not delay a high-speed safety request.
        if desiredPercent >= emergencyBypassPercent {
            filteredRuleTargetPercent = desiredPercent
            return desiredPercent
        }

        let elapsed = max(now.timeIntervalSince(previousDate), 0.01)
        let timeConstant = desiredPercent > previous
            ? rampUpTimeConstant
            : rampDownTimeConstant
        let alpha = 1.0 - exp(-elapsed / max(timeConstant, 0.01))
        let filtered = previous + alpha * (desiredPercent - previous)

        filteredRuleTargetPercent = filtered
        return filtered
    }
    
    func evaluateRules() {
        guard isRulesEngineEnabled else { return }
        
        var maxTargetPercent: Double? = nil
        
        for rule in rules where rule.isEnabled {
            guard let currentTemp = getTempFor(sensor: rule.sensor) else { continue }
            
            if rule.ruleType == .threshold {
                if currentTemp >= rule.thresholdTemp {
                    if maxTargetPercent == nil || rule.targetSpeedPercent > maxTargetPercent! {
                        maxTargetPercent = rule.targetSpeedPercent
                    }
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
                    
                    if maxTargetPercent == nil || calculatedPercent > maxTargetPercent! {
                        maxTargetPercent = calculatedPercent
                    }
                }
            }
        }
        
        let desiredPercent = maxTargetPercent ?? 0.0
        let filteredPercent = filteredRuleTarget(toward: desiredPercent, now: Date())

        // When all rules clear, ramp down to the physical fan minimum first, then
        // yield control back to macOS instead of switching to Auto abruptly.
        if desiredPercent > 0.0 || filteredPercent > releaseToAutoPercent {
            if !wasRuleApplied ||
                lastSetSpeedPercent == nil ||
                abs(filteredPercent - lastSetSpeedPercent!) >= updateResolutionPercent {
                setAllToPercentage(min(max(filteredPercent, 0.0), 100.0) / 100.0)
                lastSetSpeedPercent = filteredPercent
                wasRuleApplied = true
            }
        } else if wasRuleApplied {
            resetAll()
            wasRuleApplied = false
            lastSetSpeedPercent = nil
            resetRuleResponse()
        }
    }
    
    func getTempFor(sensor: TriggerRule.SensorType) -> Double? {
        switch sensor {
        case .cpu: return cpuTemp
        case .gpu: return gpuTemp
        case .battery: return batteryTemp
        }
    }
    
    func toggleAutoStart(_ newValue: Bool) {
        do {
            if (newValue) {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch { }
        isAutoStart = SMAppService.mainApp.status == .enabled
    }
    
    // MARK: - Temperature History Management
    private func temperatureBounds(for sensor: TriggerRule.SensorType) -> ClosedRange<Double> {
        switch sensor {
        case .cpu, .gpu:
            return 10.0...115.0
        case .battery:
            return 5.0...70.0
        }
    }

    private func maximumTemperatureStep(for sensor: TriggerRule.SensorType) -> Double {
        switch sensor {
        case .cpu, .gpu:
            return 25.0
        case .battery:
            return 8.0
        }
    }

    private func acceptTemperature(
        _ candidate: Double?,
        previous: Double?,
        sensor: TriggerRule.SensorType
    ) -> Double? {
        guard let candidate,
              candidate.isFinite,
              temperatureBounds(for: sensor).contains(candidate) else {
            return previous
        }

        // A read occurs every 1.5 seconds. Abrupt values are almost always a bad SMC
        // key or a transient decoding failure, not a real silicon-temperature change.
        if let previous,
           abs(candidate - previous) > maximumTemperatureStep(for: sensor) {
            return previous
        }
        return candidate
    }

    private func cleanHistory(_ records: [TempRecord]) -> [TempRecord] {
        var previousCPU: Double? = nil
        var previousGPU: Double? = nil
        var previousBattery: Double? = nil

        return records.map { record in
            let cpu = cleanHistoricalTemperature(record.cpu, previous: &previousCPU, sensor: .cpu)
            let gpu = cleanHistoricalTemperature(record.gpu, previous: &previousGPU, sensor: .gpu)
            let battery = cleanHistoricalTemperature(record.battery, previous: &previousBattery, sensor: .battery)
            return TempRecord(id: record.id, timestamp: record.timestamp, cpu: cpu, gpu: gpu, battery: battery)
        }
    }

    private func cleanHistoricalTemperature(
        _ candidate: Double?,
        previous: inout Double?,
        sensor: TriggerRule.SensorType
    ) -> Double? {
        guard let candidate,
              candidate.isFinite,
              temperatureBounds(for: sensor).contains(candidate) else {
            return nil
        }
        if let previous,
           abs(candidate - previous) > maximumTemperatureStep(for: sensor) {
            return nil
        }
        previous = candidate
        return candidate
    }

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
            self.tempHistory = cleanHistory(decoded)
            self.lastHistoryRecordTime = self.tempHistory.last?.timestamp
            saveHistory()
        }
    }
}
