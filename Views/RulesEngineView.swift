import SwiftUI

// MARK: - Auto-Trigger Rules Engine Views
struct RulesEngineView: View {
    @ObservedObject var viewModel: FanViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.purple)
                        Text("Auto-Trigger Rules Engine")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Automatically override fan speeds when sensors cross temperature thresholds.")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Toggle("", isOn: $viewModel.isRulesEngineEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
            }
            
            if viewModel.isRulesEngineEnabled {
                VStack(spacing: 12) {
                    ForEach($viewModel.rules) { $rule in
                        RuleRowView(rule: $rule, onDelete: {
                            if let idx = viewModel.rules.firstIndex(where: { $0.id == rule.id }) {
                                viewModel.rules.remove(at: idx)
                            }
                        })
                    }
                    
                    Button(action: {
                        withAnimation {
                            viewModel.rules.append(TriggerRule(isEnabled: true, sensor: .cpu, thresholdTemp: 60.0, targetSpeedPercent: 50.0))
                        }
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Custom Trigger Rule")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.purple)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.02))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(viewModel.isRulesEngineEnabled ? Color.purple.opacity(0.2) : Color.white.opacity(0.04), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
}

struct RuleRowView: View {
    @Binding var rule: TriggerRule
    var onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle("", isOn: $rule.isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .labelsHidden()
                
                Text("If")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                
                Picker("", selection: $rule.sensor) {
                    ForEach(TriggerRule.SensorType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 85)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                
                Text("temp ≥")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                
                Text("\(Int(rule.thresholdTemp))°C")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36)
                
                Slider(value: $rule.thresholdTemp, in: 30...95, step: 1)
                    .accentColor(.purple)
                    .frame(width: 80)
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                        .padding(6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            HStack(spacing: 12) {
                Spacer().frame(width: 48)
                Text("Set speed to")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                
                Text("\(Int(rule.targetSpeedPercent))%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36)
                
                Slider(value: $rule.targetSpeedPercent, in: 0...100, step: 5)
                    .accentColor(.purple)
                
                Spacer()
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
    }
}
