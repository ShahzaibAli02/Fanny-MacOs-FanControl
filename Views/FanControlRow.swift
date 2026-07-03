import SwiftUI

// MARK: - Individual Fan Control Row
struct FanControlRow: View, Equatable {
    let fan: FanJSON
    // Plain closures instead of an @ObservedObject on the view model: observing
    // the view model here would re-render (and re-lay-out) every row on every
    // 1.5s poll, regardless of whether this fan changed. With value inputs only,
    // Equatable lets SwiftUI prune unchanged rows from the layout pass.
    let onChangeMode: (Int) -> Void
    let onChangeSpeed: (Int) -> Void

    @State private var sliderVal: Double = 0.0
    @State private var isEditingSlider: Bool = false

    init(fan: FanJSON, onChangeMode: @escaping (Int) -> Void, onChangeSpeed: @escaping (Int) -> Void) {
        self.fan = fan
        self.onChangeMode = onChangeMode
        self.onChangeSpeed = onChangeSpeed
        // Initial setup of state
        _sliderVal = State(initialValue: Double(fan.targetSpeed))
    }

    // Closures are excluded from equality; only the fan's data drives a redraw.
    static func == (lhs: FanControlRow, rhs: FanControlRow) -> Bool {
        lhs.fan == rhs.fan
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header Info
            HStack(spacing: 16) {
                SpinningFanView(currentSpeed: Double(fan.currentSpeed), maxSpeed: Double(fan.maxSpeed))
                    .equatable()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(fan.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Text("\(fan.currentSpeed)")
                            .font(.system(size: 26, weight: .black, design: .monospaced))
                            .foregroundColor(rpmColor)
                        Text("RPM")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.gray)
                            .offset(y: 4)
                    }
                }
                
                Spacer()
                
                // Mode Select Picker
                Picker("", selection: Binding(
                    get: { fan.mode },
                    set: { newMode in
                        onChangeMode(newMode)
                    }
                )) {
                    Text("Auto").tag(0)
                    Text("Manual").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 150)
            }
            
            // Speed Controls (if Manual Mode)
            if fan.mode == 1 {
                VStack(spacing: 12) {
                    // Slider Label
                    HStack {
                        Text("Target Speed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(sliderVal)) RPM (\(Int(speedPercentage))%)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.teal)
                    }
                    
                    // Slider
                    Slider(
                        value: $sliderVal,
                        in: Double(fan.minSpeed)...Double(fan.maxSpeed),
                        step: 50.0,
                        onEditingChanged: { editing in
                            isEditingSlider = editing
                            if !editing {
                                onChangeSpeed(Int(sliderVal))
                            }
                        }
                    )
                    .accentColor(.teal)
                    
                    // Presets
                    HStack(spacing: 8) {
                        presetButton(title: "Min", val: Double(fan.minSpeed))
                        presetButton(title: "20%", val: getSpeedForPercentage(0.20))
                        presetButton(title: "50%", val: getSpeedForPercentage(0.50))
                        presetButton(title: "80%", val: getSpeedForPercentage(0.80))
                        presetButton(title: "Max", val: Double(fan.maxSpeed))
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.gray)
                    Text("Mac system thermal controller is managing this fan.")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.03))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        // Keep slider synchronized with system status updates if user is not actively dragging it
        .onChange(of: fan.targetSpeed) { newTarget in
            if !isEditingSlider {
                sliderVal = Double(newTarget)
            }
        }
    }
    
    var rpmColor: Color {
        let ratio = Double(fan.currentSpeed) / Double(fan.maxSpeed > 0 ? fan.maxSpeed : 6000)
        if ratio > 0.75 {
            return .orange
        } else if ratio > 0.4 {
            return .teal
        } else {
            return .blue
        }
    }
    
    var speedPercentage: Double {
        let range = Double(fan.maxSpeed - fan.minSpeed)
        guard range > 0 else { return 0 }
        return ((sliderVal - Double(fan.minSpeed)) / range) * 100.0
    }
    
    func getSpeedForPercentage(_ pct: Double) -> Double {
        let range = Double(fan.maxSpeed - fan.minSpeed)
        return Double(fan.minSpeed) + range * pct
    }
    
    func presetButton(title: String, val: Double) -> some View {
        Button(action: {
            sliderVal = val
            onChangeSpeed(Int(val))
        }) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
