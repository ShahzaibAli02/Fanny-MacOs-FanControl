import Foundation

// MARK: - Models for JSON Parsing
struct FanJSON: Codable, Identifiable, Equatable {
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
    var ruleType: RuleType = .threshold
    var minTemp: Double = 40.0
    var maxTemp: Double = 80.0
    var minSpeedPercent: Double = 20.0
    var maxSpeedPercent: Double = 100.0
    var reduceOnBattery: Bool = true

    enum SensorType: String, Codable, CaseIterable {
        case cpu = "CPU"
        case gpu = "GPU"
        case battery = "Battery"
    }

    enum RuleType: String, Codable, CaseIterable {
        case threshold = "Threshold"
        case curve = "Min/Max Curve"
    }

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        sensor: SensorType = .cpu,
        thresholdTemp: Double = 45.0,
        targetSpeedPercent: Double = 50.0,
        ruleType: RuleType = .threshold,
        minTemp: Double = 40.0,
        maxTemp: Double = 80.0,
        minSpeedPercent: Double = 20.0,
        maxSpeedPercent: Double = 100.0,
        reduceOnBattery: Bool = true
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.sensor = sensor
        self.thresholdTemp = thresholdTemp
        self.targetSpeedPercent = targetSpeedPercent
        self.ruleType = ruleType
        self.minTemp = minTemp
        self.maxTemp = maxTemp
        self.minSpeedPercent = minSpeedPercent
        self.maxSpeedPercent = maxSpeedPercent
        self.reduceOnBattery = reduceOnBattery
    }

    enum CodingKeys: String, CodingKey {
        case id, isEnabled, sensor, thresholdTemp, targetSpeedPercent, ruleType, minTemp, maxTemp, minSpeedPercent, maxSpeedPercent, reduceOnBattery
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sensor = try container.decodeIfPresent(SensorType.self, forKey: .sensor) ?? .cpu
        thresholdTemp = try container.decodeIfPresent(Double.self, forKey: .thresholdTemp) ?? 45.0
        targetSpeedPercent = try container.decodeIfPresent(Double.self, forKey: .targetSpeedPercent) ?? 50.0
        ruleType = try container.decodeIfPresent(RuleType.self, forKey: .ruleType) ?? .threshold
        minTemp = try container.decodeIfPresent(Double.self, forKey: .minTemp) ?? 40.0
        maxTemp = try container.decodeIfPresent(Double.self, forKey: .maxTemp) ?? 80.0
        minSpeedPercent = try container.decodeIfPresent(Double.self, forKey: .minSpeedPercent) ?? 20.0
        maxSpeedPercent = try container.decodeIfPresent(Double.self, forKey: .maxSpeedPercent) ?? 100.0
        reduceOnBattery = try container.decodeIfPresent(Bool.self, forKey: .reduceOnBattery) ?? true
    }
}
