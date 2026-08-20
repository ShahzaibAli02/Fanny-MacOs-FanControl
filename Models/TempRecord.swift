import Foundation

public struct TempRecord: Identifiable, Codable, Equatable {
    public var id: UUID
    public let timestamp: Date
    public let cpu: Double?
    public let gpu: Double?
    public let battery: Double?
    public let fanTargetPercent: Double?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        cpu: Double?,
        gpu: Double?,
        battery: Double?,
        fanTargetPercent: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.battery = battery
        self.fanTargetPercent = fanTargetPercent
    }
}
