//
//  main.swift
//  Fan Control Helper CLI
//

import Foundation

struct FanJSON: Codable {
    let id: Int
    let name: String
    let currentSpeed: Int
    let minSpeed: Int
    let maxSpeed: Int
    let targetSpeed: Int
    let mode: Int
}

struct SystemStatusJSON: Codable {
    let fans: [FanJSON]
    let cpuTemp: Double?
    let gpuTemp: Double?
    let batteryTemp: Double?
}

func printHelp() {
    let help = """
    SMC Fan Control Helper CLI
    Usage:
      smc-helper get
      smc-helper set <fanId> <mode> [<speed>]   (mode: 0 = auto, 1 = manual; speed in RPM)
      smc-helper reset
    """
    print(help)
}

func getStatus() {
    let smc = SMC.shared
    
    guard let fanCountVal = smc.getValue("FNum") else {
        print("{}")
        return
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
    
    // Read typical temperature sensors with comprehensive Intel / Apple Silicon fallback list
    let cpuKeys = [
        "TC0P", "TC0D", "TC0F", "TC1C", "TCAD", "TCBD",
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0C", "Tp0g", "Tp0h", "Te0S"
    ]
    let gpuKeys = [
        "TG0D", "TG0H", "TG0P",
        "Tg05", "Tg0j", "Tg0g", "Tg01", "Tg0c"
    ]
    let batteryKeys = [
        "TB0T", "TB1T", "TB2T", "Tw0P", "Ts0P", "Th0H"
    ]
    
    func getFirstValidTemp(keys: [String]) -> Double? {
        for key in keys {
            if let val = smc.getValue(key), val > 0 && val < 150 {
                return val
            }
        }
        return nil
    }
    
    let cpuTemp = getFirstValidTemp(keys: cpuKeys)
    let gpuTemp = getFirstValidTemp(keys: gpuKeys)
    let batteryTemp = getFirstValidTemp(keys: batteryKeys)
    
    let status = SystemStatusJSON(
        fans: fansList,
        cpuTemp: cpuTemp,
        gpuTemp: gpuTemp,
        batteryTemp: batteryTemp
    )
    
    if let jsonData = try? JSONEncoder().encode(status),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        print(jsonString)
    } else {
        print("{}")
    }
}

func setFan(fanId: Int, mode: Int, speed: Int?) {
    let smc = SMC.shared
    
    if mode == 0 {
        // Automatic mode
        let success = smc.setFanMode(fanId, mode: .automatic)
        if success {
            print("SUCCESS: Fan \(fanId) set to Automatic")
        } else {
            print("ERROR: Failed to set Fan \(fanId) to Automatic")
            exit(1)
        }
    } else if mode == 1 {
        // Manual mode
        guard let targetSpeed = speed else {
            print("ERROR: Speed in RPM is required for manual mode")
            exit(1)
        }
        
        // 1. Set mode to forced
        let modeSuccess = smc.setFanMode(fanId, mode: .forced)
        guard modeSuccess else {
            print("ERROR: Failed to set Fan \(fanId) mode to Manual")
            exit(1)
        }
        
        // 2. Set speed
        let speedSuccess = smc.setFanSpeed(fanId, speed: targetSpeed)
        if speedSuccess {
            print("SUCCESS: Fan \(fanId) set to Manual (\(targetSpeed) RPM)")
        } else {
            print("ERROR: Failed to set Fan \(fanId) speed to \(targetSpeed) RPM")
            exit(1)
        }
    } else {
        print("ERROR: Invalid mode. Use 0 for auto, 1 for manual.")
        exit(1)
    }
}

func main() {
    let args = CommandLine.arguments
    guard args.count > 1 else {
        printHelp()
        return
    }
    
    let cmd = args[1].lowercased()
    
    switch cmd {
    case "get":
        getStatus()
    case "set":
        guard args.count >= 4 else {
            print("ERROR: Missing arguments for 'set'")
            printHelp()
            exit(1)
        }
        guard let fanId = Int(args[2]), let mode = Int(args[3]) else {
            print("ERROR: Invalid fanId or mode")
            exit(1)
        }
        let speed = args.count > 4 ? Int(args[4]) : nil
        setFan(fanId: fanId, mode: mode, speed: speed)
    case "reset":
        #if arch(arm64)
        let success = SMC.shared.resetFanControl()
        if success {
            print("SUCCESS: Reset fan controls")
        } else {
            print("ERROR: Failed to reset fan controls")
            exit(1)
        }
        #else
        print("SUCCESS: Reset not required on Intel Macs")
        #endif
    default:
        print("ERROR: Unknown command '\(cmd)'")
        printHelp()
        exit(1)
    }
}

main()
