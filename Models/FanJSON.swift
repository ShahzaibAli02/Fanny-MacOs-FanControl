import Foundation

// MARK: - Models for JSON Parsing
struct FanJSON: Codable, Identifiable {
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

// MARK: - Auto-Trigger Rules Model
struct TriggerRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var isEnabled: Bool = true
    var sensor: SensorType = .cpu
    var thresholdTemp: Double = 45.0
    var targetSpeedPercent: Double = 50.0
    
    enum SensorType: String, Codable, CaseIterable {
        case cpu = "CPU"
        case gpu = "GPU"
        case battery = "Battery"
    }
}
