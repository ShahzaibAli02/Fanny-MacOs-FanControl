import SwiftUI
import Charts

struct TempHistoryChartView: View {
    private let summaryLabelWidth: CGFloat = 48
    private let summaryColumnWidth: CGFloat = 148

    enum ChartSeries: Hashable {
        case sensor(TriggerRule.SensorType)
        case fanTarget
    }

    private enum TimeWindow: String, CaseIterable, Identifiable {
        case thirtyMinutes
        case oneHour
        case twoHours
        case twelveHours
        case twentyFourHours

        var id: String { rawValue }

        var interval: TimeInterval {
            switch self {
            case .thirtyMinutes: return 30 * 60
            case .oneHour: return 60 * 60
            case .twoHours: return 2 * 60 * 60
            case .twelveHours: return 12 * 60 * 60
            case .twentyFourHours: return 24 * 60 * 60
            }
        }

        var label: String {
            switch self {
            case .thirtyMinutes: return L10n.text("Last 30 min")
            case .oneHour: return L10n.text("Last hour")
            case .twoHours: return L10n.text("Last 2 hours")
            case .twelveHours: return L10n.text("Last 12 hours")
            case .twentyFourHours: return L10n.text("Last 24 hours")
            }
        }
    }

    let history: [TempRecord]
    let compactLayout: Bool

    @State private var hoveredTime: Date? = nil
    @AppStorage("temperatureHistoryDisplayWindow") private var timeWindowRawValue = TimeWindow.twoHours.rawValue
    @AppStorage("showCPUHistory") private var showCPUHistory = true
    @AppStorage("showGPUHistory") private var showGPUHistory = true
    @AppStorage("showBatteryHistory") private var showBatteryHistory = true
    @AppStorage("showFanTargetHistory") private var showFanTargetHistory = true

    struct ChartPoint: Identifiable {
        let id: String
        let series: ChartSeries
        let time: Date
        let value: Double
    }

    private var selectedTimeWindow: TimeWindow {
        TimeWindow(rawValue: timeWindowRawValue) ?? .twoHours
    }

    private var selectedSensors: [TriggerRule.SensorType] {
        var sensors: [TriggerRule.SensorType] = []
        if showCPUHistory { sensors.append(.cpu) }
        if showGPUHistory { sensors.append(.gpu) }
        if showBatteryHistory { sensors.append(.battery) }
        return sensors
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(
            selectedTimeWindow == .twentyFourHours ? "MMM d HH:mm" : "HH:mm"
        )
        return formatter
    }

    private func sensorName(_ sensor: TriggerRule.SensorType) -> String {
        switch sensor {
        case .cpu: return L10n.text("CPU")
        case .gpu: return L10n.text("GPU")
        case .battery: return L10n.text("Battery")
        }
    }

    private func sensorColor(_ sensor: TriggerRule.SensorType) -> Color {
        switch sensor {
        case .cpu: return .orange
        case .gpu: return .purple
        case .battery: return .green
        }
    }

    private func sensorIcon(_ sensor: TriggerRule.SensorType) -> String {
        switch sensor {
        case .cpu: return "cpu"
        case .gpu: return "gauge.with.needle"
        case .battery: return "battery.100.bolt"
        }
    }

    private func seriesName(_ series: ChartSeries) -> String {
        switch series {
        case .sensor(let sensor): return sensorName(sensor)
        case .fanTarget: return L10n.text("Fan target")
        }
    }

    private func seriesColor(_ series: ChartSeries) -> Color {
        switch series {
        case .sensor(let sensor): return sensorColor(sensor)
        case .fanTarget: return .cyan
        }
    }

    private func value(for sensor: TriggerRule.SensorType, in record: TempRecord) -> Double? {
        switch sensor {
        case .cpu: return record.cpu
        case .gpu: return record.gpu
        case .battery: return record.battery
        }
    }

    private func points(
        for sensor: TriggerRule.SensorType,
        from windowStart: Date,
        through now: Date
    ) -> [ChartPoint] {
        history.compactMap { record in
            guard record.timestamp >= windowStart,
                  record.timestamp <= now,
                  let temperature = value(for: sensor, in: record) else {
                return nil
            }
            return ChartPoint(
                id: "\(record.id.uuidString)-\(sensor.rawValue)",
                series: .sensor(sensor),
                time: record.timestamp,
                value: temperature
            )
        }
    }

    private func fanTargetPoints(from windowStart: Date, through now: Date) -> [ChartPoint] {
        history.compactMap { record in
            guard record.timestamp >= windowStart,
                  record.timestamp <= now,
                  let targetPercent = record.fanTargetPercent,
                  (0.0...100.0).contains(targetPercent) else {
                return nil
            }
            return ChartPoint(
                id: "\(record.id.uuidString)-fan-target",
                series: .fanTarget,
                time: record.timestamp,
                value: targetPercent
            )
        }
    }

    private func points(
        for series: ChartSeries,
        from windowStart: Date,
        through now: Date
    ) -> [ChartPoint] {
        switch series {
        case .sensor(let sensor):
            return points(for: sensor, from: windowStart, through: now)
        case .fanTarget:
            return fanTargetPoints(from: windowStart, through: now)
        }
    }

    var body: some View {
        // The graph is a rolling window ending at the present moment, rather
        // than a calendar-day view beginning at midnight.
        let now = Date()
        let windowStart = now.addingTimeInterval(-selectedTimeWindow.interval)
        let displayedSeries = selectedSensors.map(ChartSeries.sensor)
            + (showFanTargetHistory ? [.fanTarget] : [])
        let pointsBySeries: [ChartSeries: [ChartPoint]] = Dictionary(
            uniqueKeysWithValues: displayedSeries.map { series in
                (series, points(for: series, from: windowStart, through: now))
            }
        )
        let allPoints = displayedSeries.flatMap { pointsBySeries[$0] ?? [] }
        let hoverPoints = hoveredTime.map { time in
            displayedSeries.compactMap { series in
                pointsBySeries[series]?.min {
                    abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time))
                }
            }
        } ?? []
        // This is the one values strip for the chart: live values normally,
        // or values at the inspected instant while the pointer is in the graph.
        let inspectionPoints = hoverPoints.isEmpty
            ? displayedSeries.compactMap { pointsBySeries[$0]?.last }
            : hoverPoints
        let chartScaleMaximum = max(
            105.0,
            ceil((allPoints.map(\.value).max() ?? 0.0) / 5.0) * 5.0
        )

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundColor(.cyan)
                        .font(.system(size: 14, weight: .bold))
                    Text("Temperature & fan target history")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                Picker("History duration", selection: $timeWindowRawValue) {
                    ForEach(TimeWindow.allCases) { window in
                        Text(window.label).tag(window.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 112)
                .help(L10n.text("Choose the rolling time range shown in the graph"))
            }

            HStack(spacing: 10) {
                Color.clear.frame(width: summaryLabelWidth, height: 1)
                sensorToggle(.cpu, isOn: $showCPUHistory)
                    .frame(width: summaryColumnWidth, alignment: .leading)
                sensorToggle(.gpu, isOn: $showGPUHistory)
                    .frame(width: summaryColumnWidth, alignment: .leading)
                sensorToggle(.battery, isOn: $showBatteryHistory)
                    .frame(width: summaryColumnWidth, alignment: .leading)
                fanTargetToggle
                    .frame(width: summaryColumnWidth, alignment: .leading)
                Spacer(minLength: 0)
            }

            if selectedSensors.isEmpty && !showFanTargetHistory {
                emptyState(
                    icon: "chart.xyaxis.line",
                    message: "Select one or more series to display their history."
                )
            } else if allPoints.isEmpty {
                emptyState(
                    icon: "chart.xyaxis.line",
                    message: "No temperature data recorded in this time range yet."
                )
            } else {
                HStack(spacing: 10) {
                    Text(hoveredTime == nil ? L10n.text("Now") : timeFormatter.string(from: hoveredTime!))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(width: summaryLabelWidth, alignment: .leading)

                    inspectionColumn(for: .sensor(.cpu), in: inspectionPoints)
                    inspectionColumn(for: .sensor(.gpu), in: inspectionPoints)
                    inspectionColumn(for: .sensor(.battery), in: inspectionPoints)
                    inspectionColumn(for: .fanTarget, in: inspectionPoints)
                    
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)

                HStack(spacing: 10) {
                    Text("Range")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(width: summaryLabelWidth, alignment: .leading)
                    periodRangeColumn(for: .sensor(.cpu), points: pointsBySeries[.sensor(.cpu)])
                    periodRangeColumn(for: .sensor(.gpu), points: pointsBySeries[.sensor(.gpu)])
                    periodRangeColumn(for: .sensor(.battery), points: pointsBySeries[.sensor(.battery)])
                    periodRangeColumn(for: .fanTarget, points: pointsBySeries[.fanTarget])
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.035))
                .cornerRadius(6)

                Text("Shared scale: temperature in °C; blue fan target in % (limited to 100%).")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)

                Chart {
                    ForEach(selectedSensors, id: \.self) { sensor in
                        ForEach(pointsBySeries[.sensor(sensor)] ?? []) { point in
                            LineMark(
                                x: .value("Time", point.time),
                                y: .value("Temperature", point.value),
                                series: .value("Sensor", sensor.rawValue)
                            )
                            .foregroundStyle(sensorColor(sensor))
                            .interpolationMethod(.monotone)
                        }
                    }

                    if showFanTargetHistory {
                        ForEach(pointsBySeries[.fanTarget] ?? []) { point in
                            LineMark(
                                x: .value("Time", point.time),
                                y: .value("Fan target", point.value),
                                series: .value("Series", "Fan target")
                            )
                            .foregroundStyle(Color.cyan)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                            .interpolationMethod(.stepCenter)
                        }
                    }

                    if let hoveredTime {
                        RuleMark(x: .value("Hover Time", hoveredTime))
                            .foregroundStyle(Color.white.opacity(0.25))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                        ForEach(hoverPoints) { point in
                            PointMark(
                                x: .value("Hover Time", point.time),
                                y: .value("Hover Value", point.value)
                            )
                            .foregroundStyle(seriesColor(point.series))
                            .symbolSize(80)
                        }
                    }
                }
                .chartXScale(domain: windowStart...now)
                .chartYScale(domain: 0.0...chartScaleMaximum)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8))
                            .foregroundStyle(Color.white.opacity(0.14))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                            .foregroundStyle(Color.white.opacity(0.18))
                        AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                            .foregroundStyle(Color.gray)
                            .font(.system(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .stride(by: 5)) { value in
                        if let temperature = value.as(Double.self) {
                            let roundedTemperature = Int(temperature.rounded())
                            let isMajor = roundedTemperature.isMultiple(of: 10)
                            AxisGridLine(stroke: StrokeStyle(lineWidth: isMajor ? 0.9 : 0.4))
                                .foregroundStyle(Color.white.opacity(isMajor ? 0.18 : 0.08))
                            if isMajor {
                                AxisTick(stroke: StrokeStyle(lineWidth: 0.9))
                                    .foregroundStyle(Color.white.opacity(0.22))
                            AxisValueLabel {
                                Text(String(format: "%.0f", temperature))
                                        .foregroundColor(.gray)
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { _ in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        updateHoveredTime(at: value.location.x, using: proxy, from: allPoints)
                                    }
                                    .onEnded { _ in
                                        hoveredTime = nil
                                    }
                            )
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    updateHoveredTime(at: location.x, using: proxy, from: allPoints)
                                case .ended:
                                    hoveredTime = nil
                                }
                            }
                    }
                }
                .frame(height: compactLayout ? 160 : 240)
            }
        }
        .padding(compactLayout ? 12 : 16)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .onChange(of: displayedSeries) { _ in
            hoveredTime = nil
        }
        .onChange(of: timeWindowRawValue) { _ in
            hoveredTime = nil
        }
    }

    private func sensorToggle(_ sensor: TriggerRule.SensorType, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(sensorName(sensor), systemImage: sensorIcon(sensor))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(sensorColor(sensor))
        }
        .toggleStyle(CheckboxToggleStyle())
        .help(L10n.format("Show %@ temperature in the graph", sensorName(sensor)))
    }

    private var fanTargetToggle: some View {
        Toggle(isOn: $showFanTargetHistory) {
            Label("Fan target", systemImage: "fanblades")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.cyan)
        }
        .toggleStyle(CheckboxToggleStyle())
        .help(L10n.text("Show the highest requested fan speed as a percentage"))
    }

    private func emptyState(icon: String, message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.gray.opacity(0.5))
            Text(L10n.text(message))
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .frame(height: compactLayout ? 56 : 72)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.15))
        .cornerRadius(8)
    }

    private func inspectionValue(_ point: ChartPoint) -> some View {
        HStack(spacing: 4) {
            Text(seriesName(point.series))
                .foregroundColor(seriesColor(point.series))
            Text(
                point.series == .fanTarget
                    ? String(format: "%.1f%%", point.value)
                    : String(format: "%.1f°C", point.value)
            )
            .fontWeight(.bold)
            .foregroundColor(.white)
        }
        .font(.system(size: 10, weight: .medium))
    }

    private func inspectionColumn(for series: ChartSeries, in points: [ChartPoint]) -> some View {
        Group {
            if let point = points.first(where: { $0.series == series }) {
                inspectionValue(point)
            } else {
                Color.clear
            }
        }
        .frame(width: summaryColumnWidth, alignment: .leading)
    }

    private func periodRangeColumn(for series: ChartSeries, points: [ChartPoint]?) -> some View {
        Group {
            if let points, !points.isEmpty {
                periodRange(series: series, points: points)
            } else {
                Color.clear
            }
        }
        .frame(width: summaryColumnWidth, alignment: .leading)
    }

    private func periodRange(series: ChartSeries, points: [ChartPoint]) -> some View {
        let minimum = points.map(\.value).min() ?? 0
        let maximum = points.map(\.value).max() ?? 0
        let unit = series == .fanTarget ? "%" : "°C"

        return HStack(spacing: 4) {
            Text(seriesName(series))
                .foregroundColor(seriesColor(series))
            Text(String(format: "%.1f–%.1f%@", minimum, maximum, unit))
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .font(.system(size: 9, weight: .medium))
    }

    private func updateHoveredTime(
        at xPosition: CGFloat,
        using proxy: ChartProxy,
        from points: [ChartPoint]
    ) {
        guard let date: Date = proxy.value(atX: xPosition) else { return }
        hoveredTime = points.min {
            abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date))
        }?.time
    }
}
