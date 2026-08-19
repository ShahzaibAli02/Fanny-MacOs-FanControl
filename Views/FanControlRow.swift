import SwiftUI

// MARK: - Individual Fan Control Row
struct FanControlRow: View {
    let fan: FanJSON
    @ObservedObject var viewModel: FanViewModel
    let compactLayout: Bool
    
    @State private var sliderVal: Double = 0.0
    @State private var isEditingSlider: Bool = false
    
    init(fan: FanJSON, viewModel: FanViewModel, compactLayout: Bool = false) {
        self.fan = fan
        self.viewModel = viewModel
        self.compactLayout = compactLayout
        // Initial setup of state
        _sliderVal = State(initialValue: Double(fan.targetSpeed))
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: compactLayout ? 12 : 18) {
            SpinningFanView(currentSpeed: Double(fan.currentSpeed), maxSpeed: Double(fan.maxSpeed))
                // NSViewRepresentable must be constrained explicitly; otherwise
                // SwiftUI may offer it the entire width of a resized row.
                // Treat the fan as the leading visual column, not as a small
                // top-aligned badge beside a taller group of controls.
                .frame(width: compactLayout ? 88 : 140, height: compactLayout ? 88 : 140)

            VStack(alignment: .leading, spacing: compactLayout ? 6 : 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fan.name)
                            .font(.system(size: compactLayout ? 14 : 16, weight: .bold))
                            .foregroundColor(.white)

                        HStack(spacing: 8) {
                            Text("\(fan.currentSpeed)")
                                .font(.system(size: compactLayout ? 21 : 26, weight: .black, design: .monospaced))
                                .foregroundColor(rpmColor)
                            Text("RPM")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gray)
                                .offset(y: 4)
                        }
                    }

                    Spacer(minLength: 12)

                    Picker("", selection: Binding(
                        get: { fan.mode },
                        set: { newMode in
                            viewModel.changeFanMode(fanId: fan.id, mode: newMode)
                        }
                    )) {
                        Text("Auto").tag(0)
                        Text("Manual").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: compactLayout ? 128 : 150)
                }

                if fan.mode == 1 {
                    VStack(spacing: compactLayout ? 5 : 8) {
                        HStack {
                            Text("Target Speed")
                                .font(.system(size: compactLayout ? 10 : 12, weight: .semibold))
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(Int(sliderVal)) RPM (\(Int(speedPercentage))%)")
                                .font(.system(size: compactLayout ? 10 : 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.teal)
                        }

                        Slider(
                            value: $sliderVal,
                            in: Double(fan.minSpeed)...Double(fan.maxSpeed),
                            step: 50.0,
                            onEditingChanged: { editing in
                                isEditingSlider = editing
                                if !editing {
                                    viewModel.changeFanSpeed(fanId: fan.id, speed: Int(sliderVal))
                                }
                            }
                        )
                        .accentColor(.teal)

                        HStack(spacing: compactLayout ? 5 : 8) {
                            presetButton(title: "Min", val: Double(fan.minSpeed), compact: compactLayout)
                            presetButton(title: "20%", val: getSpeedForPercentage(0.20), compact: compactLayout)
                            presetButton(title: "50%", val: getSpeedForPercentage(0.50), compact: compactLayout)
                            presetButton(title: "80%", val: getSpeedForPercentage(0.80), compact: compactLayout)
                            presetButton(title: "Max", val: Double(fan.maxSpeed), compact: compactLayout)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if !compactLayout {
                    Label("Mac system thermal controller is managing this fan.", systemImage: "cpu")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .padding(.top, 2)
                }
            }
        }
        .padding(compactLayout ? 12 : 18)
        .background(Color.white.opacity(0.03))
        .cornerRadius(compactLayout ? 12 : 16)
        .overlay(
            RoundedRectangle(cornerRadius: compactLayout ? 12 : 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
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
    
    func presetButton(title: String, val: Double, compact: Bool) -> some View {
        Button(action: {
            sliderVal = val
            viewModel.changeFanSpeed(fanId: fan.id, speed: Int(val))
        }) {
            Text(title)
                .font(.system(size: compact ? 9 : 11, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 4 : 6)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
