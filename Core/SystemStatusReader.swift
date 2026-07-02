import Foundation

// In-process equivalent of `smc-helper get`. SMC reads don't require root,
// so the GUI can query sensors directly instead of forking the privileged
// helper on every poll cycle.
enum SystemStatusReader {
    private static let cpuKeys = [
        "TC0P", "TC0D", "TC0F", "TC1C", "TCAD", "TCBD",
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0C", "Tp0g", "Tp0h", "Te0S"
    ]
    private static let gpuKeys = [
        "TG0D", "TG0H", "TG0P",
        "Tg05", "Tg0j", "Tg0g", "Tg01", "Tg0c"
    ]
    private static let batteryKeys = [
        "TB0T", "TB1T", "TB2T", "Tw0P", "Ts0P", "Th0H"
    ]

    static func read() -> SystemStatusJSON {
        let smc = SMC.shared

        guard let fanCountVal = smc.getValue("FNum") else {
            return SystemStatusJSON(fans: [], cpuTemp: nil, gpuTemp: nil, batteryTemp: nil)
        }

        let fanCount = Int(fanCountVal)
        var fansList: [FanJSON] = []

        for i in 0..<fanCount {
            let name = smc.getStringValue("F\(i)ID") ?? "Fan \(i)"
            let current = Int(smc.getValue("F\(i)Ac") ?? 0)
            let minS = Int(smc.getValue("F\(i)Mn") ?? 0)
            let maxS = Int(smc.getValue("F\(i)Mx") ?? 0)
            let target = Int(smc.getValue("F\(i)Tg") ?? 0)

            let modeKey = smc.fanModeKey(i)
            let mode = Int(smc.getValue(modeKey) ?? 0)

            fansList.append(FanJSON(
                id: i,
                name: name,
                currentSpeed: current,
                minSpeed: minS,
                maxSpeed: maxS,
                targetSpeed: target,
                mode: mode
            ))
        }

        return SystemStatusJSON(
            fans: fansList,
            cpuTemp: firstValidTemp(smc, keys: cpuKeys),
            gpuTemp: firstValidTemp(smc, keys: gpuKeys),
            batteryTemp: firstValidTemp(smc, keys: batteryKeys)
        )
    }

    private static func firstValidTemp(_ smc: SMC, keys: [String]) -> Double? {
        for key in keys {
            if let val = smc.getValue(key), val > 0 && val < 150 {
                return val
            }
        }
        return nil
    }
}
