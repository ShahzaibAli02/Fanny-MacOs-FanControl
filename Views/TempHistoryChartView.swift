import SwiftUI
import Charts

struct TempHistoryChartView: View, Equatable {
    let sensor: TriggerRule.SensorType
    let history: [TempRecord]
    let onClose: () -> Void

    @State private var hoveredPoint: ChartPoint? = nil

    // Max number of points actually drawn. The history holds up to 12h of 30s
    // samples (~1440 points); rendering every one is what made a single layout
    // pass of this chart expensive. Downsampling caps the mark count.
    private static let maxRenderedPoints = 120

    // Only the data drives the chart. Excluding the closure lets `.equatable()`
    // prune this subtree from the layout pass on polls where history is
    // unchanged (history only records every 30s, but sensors update every 1.5s).
    static func == (lhs: TempHistoryChartView, rhs: TempHistoryChartView) -> Bool {
        lhs.sensor == rhs.sensor && lhs.history == rhs.history
    }

    struct ChartPoint: Identifiable {
        let id = UUID()
        let time: Date
        let value: Double
    }

    // Evenly strides the points down to at most `maxRenderedPoints`, always
    // keeping the last (most recent) sample so "CURRENT" stays accurate.
    private func downsample(_ pts: [ChartPoint]) -> [ChartPoint] {
        guard pts.count > Self.maxRenderedPoints else { return pts }
        let step = Double(pts.count) / Double(Self.maxRenderedPoints)
        var result: [ChartPoint] = []
        result.reserveCapacity(Self.maxRenderedPoints + 1)
        var cursor = 0.0
        while Int(cursor) < pts.count {
            result.append(pts[Int(cursor)])
            cursor += step
        }
        if let last = pts.last, result.last?.id != last.id {
            result.append(last)
        }
        return result
    }
    
    var sensorColor: Color {
        switch sensor {
        case .cpu: return .orange
        case .gpu: return .purple
        case .battery: return .green
        }
    }
    
    var sensorIconName: String {
        switch sensor {
        case .cpu: return "cpu"
        case .gpu: return "gauge.with.needle"
        case .battery: return "battery.100.bolt"
        }
    }
    
    var sensorName: String {
        switch sensor {
        case .cpu: return "CPU Die"
        case .gpu: return "GPU proximity"
        case .battery: return "Battery"
        }
    }
    
    func valueForSensor(_ record: TempRecord) -> Double? {
        switch sensor {
        case .cpu: return record.cpu
        case .gpu: return record.gpu
        case .battery: return record.battery
        }
    }
    
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }
    
    var body: some View {
        // Map all available history points to sensor values
        let points = history
            .compactMap { record -> ChartPoint? in
                if let val = valueForSensor(record) {
                    return ChartPoint(time: record.timestamp, value: val)
                }
                return nil
            }
        
        let statsMin = points.map { $0.value }.min() ?? 0
        let statsMax = points.map { $0.value }.max() ?? 0
        let statsAvg = points.isEmpty ? 0 : points.map { $0.value }.reduce(0, +) / Double(points.count)

        // Marks and hover hit-testing run against the downsampled set; the stats
        // above stay on the full history for accuracy (that scan is cheap).
        let sampled = downsample(points)
        
        VStack(spacing: 14) {
            // Header: Title + Sensor Type + Close button
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: sensorIconName)
                        .foregroundColor(sensorColor)
                        .font(.system(size: 14, weight: .bold))
                    Text("\(sensorName) Temperature History")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if points.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 24))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No temperature data recorded yet.")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.15))
                .cornerRadius(8)
            } else {
                // Statistics Row
                HStack(spacing: 24) {
                    StatItem(title: "CURRENT", value: String(format: "%.1f°C", points.last?.value ?? 0), color: sensorColor)
                    StatItem(title: "AVERAGE", value: String(format: "%.1f°C", statsAvg), color: .white.opacity(0.8))
                    StatItem(title: "MIN / MAX", value: String(format: "%.1f°C / %.1f°C", statsMin, statsMax), color: .white.opacity(0.8))
                    
                    Spacer()
                    
                    if let hovered = hoveredPoint {
                        HStack(spacing: 4) {
                            Circle().fill(sensorColor).frame(width: 6, height: 6)
                            Text("\(timeFormatter.string(from: hovered.time)):")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.gray)
                            Text(String(format: "%.1f°C", hovered.value))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                    }
                }
                
                // Swift Chart
                Chart {
                    ForEach(sampled) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Temperature", point.value)
                        )
                        .foregroundStyle(sensorColor)
                        .interpolationMethod(.monotone)
                        
                        AreaMark(
                            x: .value("Time", point.time),
                            y: .value("Temperature", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [sensorColor.opacity(0.2), sensorColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    
                    if let hovered = hoveredPoint {
                        RuleMark(x: .value("Hover Time", hovered.time))
                            .foregroundStyle(Color.white.opacity(0.25))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        
                        PointMark(
                            x: .value("Hover Time", hovered.time),
                            y: .value("Hover Temp", hovered.value)
                        )
                        .foregroundStyle(.white)
                        .symbolSize(80)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.05))
                        AxisValueLabel()
                            .foregroundStyle(Color.gray)
                            .font(.system(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.05))
                        if let tempVal = value.as(Double.self) {
                            AxisValueLabel {
                                Text(String(format: "%.0f°C", tempVal))
                                    .foregroundColor(.gray)
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if let date: Date = proxy.value(atX: value.location.x) {
                                            if let closest = sampled.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }) {
                                                hoveredPoint = closest
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        hoveredPoint = nil
                                    }
                            )
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let date: Date = proxy.value(atX: location.x) {
                                        if let closest = sampled.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }) {
                                            hoveredPoint = closest
                                        }
                                    }
                                case .ended:
                                    hoveredPoint = nil
                                }
                            }
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Mini Stats Component
struct StatItem: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
        }
    }
}
