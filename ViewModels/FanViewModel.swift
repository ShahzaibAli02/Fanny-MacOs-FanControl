import SwiftUI
import AppKit

// MARK: - View Model
class FanViewModel: ObservableObject {
    @Published var fans: [FanJSON] = []
    @Published var cpuTemp: Double? = nil
    @Published var gpuTemp: Double? = nil
    @Published var batteryTemp: Double? = nil
    
    @Published var isAuthorized: Bool = false
    @Published var linkedFans: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isPollingActive: Bool = false
    
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
        
        var error: NSDictionary? = nil
        appleScript.executeAndReturnError(&error)
        
        if let err = error {
            let desc = err[NSAppleScript.errorMessage] as? String ?? "Authorization rejected or failed."
            self.errorMessage = desc
            self.isAuthorized = false
        } else {
            self.errorMessage = nil
            self.isAuthorized = true
            self.updateStatus()
        }
    }
    
    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        updateStatus()
    }
    
    func updateStatus() {
        let path = helperPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        
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
                    self.cpuTemp = decoded.cpuTemp
                    self.gpuTemp = decoded.gpuTemp
                    self.batteryTemp = decoded.batteryTemp
                    self.isPollingActive = true
                    self.evaluateRules()
                }
            }
        } catch {
            print("Status fetch failed: \(error)")
        }
    }
    
    func setFanMode(fanId: Int, mode: Int, speed: Int? = nil) {
        let path = helperPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        
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
            updateStatus()
        } catch {
            print("Set fan failed: \(error)")
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
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["reset"]
        
        do {
            try task.run()
            task.waitUntilExit()
            updateStatus()
        } catch {
            print("Reset failed: \(error)")
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
    
    func evaluateRules() {
        guard isRulesEngineEnabled else { return }
        
        var maxTargetPercent: Double? = nil
        
        for rule in rules where rule.isEnabled {
            guard let currentTemp = getTempFor(sensor: rule.sensor) else { continue }
            
            if currentTemp >= rule.thresholdTemp {
                if maxTargetPercent == nil || rule.targetSpeedPercent > maxTargetPercent! {
                    maxTargetPercent = rule.targetSpeedPercent
                }
            }
        }
        
        if let targetPercent = maxTargetPercent {
            let speedFraction = targetPercent / 100.0
            if !wasRuleApplied || lastSetSpeedPercent != targetPercent {
                setAllToPercentage(speedFraction)
                lastSetSpeedPercent = targetPercent
                wasRuleApplied = true
            }
        } else {
            if wasRuleApplied {
                resetAll()
                wasRuleApplied = false
                lastSetSpeedPercent = nil
            }
        }
    }
    
    func getTempFor(sensor: TriggerRule.SensorType) -> Double? {
        switch sensor {
        case .cpu: return cpuTemp
        case .gpu: return gpuTemp
        case .battery: return batteryTemp
        }
    }
}
