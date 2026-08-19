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
    private let historyRetentionInterval: TimeInterval = 24 * 60 * 60
    
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
    @Published var maximumCommandRiseRatePercentPerSecond: Double = 6.0 {
        didSet {
            UserDefaults.standard.set(
                maximumCommandRiseRatePercentPerSecond,
                forKey: "maximumCommandRiseRatePercentPerSecond"
            )
        }
    }
    @Published var maximumCommandFallRatePercentPerSecond: Double = 3.0 {
        didSet {
            UserDefaults.standard.set(
                maximumCommandFallRatePercentPerSecond,
                forKey: "maximumCommandFallRatePercentPerSecond"
            )
        }
    }
    @Published var coolingTemperatureHysteresis: Double = 5.0 {
        didSet {
            UserDefaults.standard.set(coolingTemperatureHysteresis, forKey: "coolingTemperatureHysteresis")
        }
    }
    @Published var minimumCommandChangePercent: Double = 4.0 {
        didSet {
            UserDefaults.standard.set(minimumCommandChangePercent, forKey: "minimumCommandChangePercent")
        }
    }
    @Published var coolingConfirmationSeconds: Double = 8.0 {
        didSet {
            UserDefaults.standard.set(coolingConfirmationSeconds, forKey: "coolingConfirmationSeconds")
        }
    }
    private var wasRuleApplied = false
    private var lastSetSpeedPercent: Double? = nil
    private var filteredRuleTargetPercent: Double? = nil
    private var deadbandedRuleTargetPercent: Double? = nil
    private var lastRuleEvaluationDate: Date? = nil
    private var heldControlTemperatures: [TriggerRule.SensorType: Double] = [:]
    private var pendingCoolingTargetPercent: Double? = nil
    private var coolingConfirmationStartDate: Date? = nil

    private let emergencyBypassPercent = 90.0
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
        // Thermal protection is independent of the window's visibility. The SMC is
        // sampled at the same one-second cadence whether the app is frontmost,
        // covered, or hidden, so automatic rules always have the same response time.
        1.0
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
        if defaults.object(forKey: "maximumCommandRiseRatePercentPerSecond") != nil {
            maximumCommandRiseRatePercentPerSecond = defaults.double(
                forKey: "maximumCommandRiseRatePercentPerSecond"
            )
        }
        if defaults.object(forKey: "maximumCommandFallRatePercentPerSecond") != nil {
            maximumCommandFallRatePercentPerSecond = defaults.double(
                forKey: "maximumCommandFallRatePercentPerSecond"
            )
        }
        if defaults.object(forKey: "coolingTemperatureHysteresis") != nil {
            coolingTemperatureHysteresis = defaults.double(forKey: "coolingTemperatureHysteresis")
        }
        if defaults.object(forKey: "minimumCommandChangePercent") != nil {
            minimumCommandChangePercent = defaults.double(forKey: "minimumCommandChangePercent")
        }
        if defaults.object(forKey: "coolingConfirmationSeconds") != nil {
            coolingConfirmationSeconds = defaults.double(forKey: "coolingConfirmationSeconds")
        }
    }

    private func resetRuleResponse() {
        filteredRuleTargetPercent = nil
        deadbandedRuleTargetPercent = nil
        lastRuleEvaluationDate = nil
        heldControlTemperatures.removeAll()
        clearCoolingConfirmation()
    }

    /// Lets temperature increases through immediately, but holds the last accepted
    /// temperature while cooling until it has fallen by the selected deadband. This
    /// avoids small sensor fluctuations repeatedly reducing and restoring fan demand.
    private func temperatureForFanControl(
        _ temperature: Double,
        sensor: TriggerRule.SensorType
    ) -> Double {
        guard let heldTemperature = heldControlTemperatures[sensor] else {
            heldControlTemperatures[sensor] = temperature
            return temperature
        }

        let hysteresis = max(coolingTemperatureHysteresis, 0)
        if temperature >= heldTemperature || temperature <= heldTemperature - hysteresis {
            heldControlTemperatures[sensor] = temperature
            return temperature
        }

        return heldTemperature
    }

    /// Ignores small demand changes before they reach the command-rate limiter.
    /// Downward changes also need a sustained lower thermal demand, which avoids
    /// releasing fan speed for a short-lived dip in CPU or GPU power.
    private func deadbandedRuleTarget(toward desiredPercent: Double, now: Date) -> Double {
        guard let previous = deadbandedRuleTargetPercent else {
            deadbandedRuleTargetPercent = desiredPercent
            clearCoolingConfirmation()
            return desiredPercent
        }

        if desiredPercent >= emergencyBypassPercent {
            deadbandedRuleTargetPercent = desiredPercent
            clearCoolingConfirmation()
            return desiredPercent
        }

        let change = desiredPercent - previous
        if change >= 0 {
            // A renewed thermal demand cancels any pending cooling release.
            clearCoolingConfirmation()
            if change >= minimumCommandChangePercent {
                deadbandedRuleTargetPercent = desiredPercent
            }
            return deadbandedRuleTargetPercent ?? desiredPercent
        }

        // A thermal recovery that reverses before being confirmed starts the
        // confirmation interval again, even if it remains below the current target.
        if let pendingTarget = pendingCoolingTargetPercent,
           desiredPercent > pendingTarget {
            pendingCoolingTargetPercent = desiredPercent
            coolingConfirmationStartDate = now
        }

        guard abs(change) >= minimumCommandChangePercent else {
            return previous
        }

        let confirmationInterval = max(coolingConfirmationSeconds, 0)
        guard confirmationInterval > 0 else {
            deadbandedRuleTargetPercent = desiredPercent
            clearCoolingConfirmation()
            return desiredPercent
        }

        if pendingCoolingTargetPercent == nil {
            pendingCoolingTargetPercent = desiredPercent
            coolingConfirmationStartDate = now
            return previous
        }

        pendingCoolingTargetPercent = min(pendingCoolingTargetPercent ?? desiredPercent, desiredPercent)
        guard let startDate = coolingConfirmationStartDate,
              now.timeIntervalSince(startDate) >= confirmationInterval else {
            return previous
        }

        let confirmedTarget = pendingCoolingTargetPercent ?? desiredPercent
        deadbandedRuleTargetPercent = confirmedTarget
        clearCoolingConfirmation()
        return confirmedTarget
    }

    private func clearCoolingConfirmation() {
        pendingCoolingTargetPercent = nil
        coolingConfirmationStartDate = nil
    }

    /// Moves the automatic command at a bounded, predictable rate. This is a
    /// slew-rate limiter, rather than a time-constant filter: it gives the same
    /// maximum command change per second for a small or large temperature step.
    /// Heating uses a higher configurable rate than cooling by default, so the
    /// controller can react promptly to load while releasing fan speed gently.
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
        let change = desiredPercent - previous
        let maximumRate = change >= 0
            ? maximumCommandRiseRatePercentPerSecond
            : maximumCommandFallRatePercentPerSecond
        let maximumChange = max(maximumRate, 0.1) * elapsed
        let filtered = previous + min(max(change, -maximumChange), maximumChange)

        filteredRuleTargetPercent = filtered
        return filtered
    }
    
    func evaluateRules() {
        guard isRulesEngineEnabled else { return }
        
        var maxTargetPercent: Double? = nil
        
        for rule in rules where rule.isEnabled {
            guard let measuredTemp = getTempFor(sensor: rule.sensor) else { continue }
            let currentTemp = temperatureForFanControl(measuredTemp, sensor: rule.sensor)
            
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
        let now = Date()
        let stabilizedPercent = deadbandedRuleTarget(toward: desiredPercent, now: now)
        let filteredPercent = filteredRuleTarget(toward: stabilizedPercent, now: now)

        // When all rules clear, ramp down to the physical fan minimum first, then
        // yield control back to macOS instead of switching to Auto abruptly.
        if desiredPercent > 0.0 || filteredPercent > releaseToAutoPercent {
            let requiresEmergencyIncrease = stabilizedPercent >= emergencyBypassPercent
                && (lastSetSpeedPercent == nil || filteredPercent > lastSetSpeedPercent!)
            if !wasRuleApplied ||
                lastSetSpeedPercent == nil ||
                requiresEmergencyIncrease ||
                abs(filteredPercent - lastSetSpeedPercent!) >= 0.1 {
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
            let fanTargetPercent = record.fanTargetPercent.flatMap { candidate in
                candidate.isFinite && (0.0...100.0).contains(candidate) ? candidate : nil
            }
            return TempRecord(
                id: record.id,
                timestamp: record.timestamp,
                cpu: cpu,
                gpu: gpu,
                battery: battery,
                fanTargetPercent: fanTargetPercent
            )
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
        
        let record = TempRecord(
            timestamp: now,
            cpu: cpuTemp,
            gpu: gpuTemp,
            battery: batteryTemp,
            fanTargetPercent: highestFanTargetPercent()
        )
        tempHistory.append(record)
        lastHistoryRecordTime = now
        
        pruneHistory()
        saveHistory()
    }

    /// The history graph has one fan-target series. When fans differ, record the
    /// highest SMC target percentage so the trace remains conservative and useful
    /// for comparing thermal demand with the strongest commanded cooling response.
    private func highestFanTargetPercent() -> Double? {
        fans.compactMap { fan -> Double? in
            let range = fan.maxSpeed - fan.minSpeed
            guard range > 0 else { return nil }
            let percentage = 100.0 * Double(fan.targetSpeed - fan.minSpeed) / Double(range)
            return min(max(percentage, 0.0), 100.0)
        }
        .max()
    }
    
    private func pruneHistory() {
        let cutoff = Date().addingTimeInterval(-historyRetentionInterval)
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
            let cutoff = Date().addingTimeInterval(-historyRetentionInterval)
            self.tempHistory = cleanHistory(decoded).filter { $0.timestamp >= cutoff }
            self.lastHistoryRecordTime = self.tempHistory.last?.timestamp
            saveHistory()
        }
    }
}
