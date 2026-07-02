import SwiftUI
import AppKit

// MARK: - Main Content View
struct ContentView: View {
    @ObservedObject var viewModel: FanViewModel
    @State private var selectedSensor: TriggerRule.SensorType? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Title Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Fan Control Center")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.white)
                        
                        Text("v2.0")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                    }
                    Text("Mac System SMC Monitoring & Adjustment")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                
                Spacer()

                // Power Source Badge
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isOnACPower ? "powerplug.fill" : "battery.75")
                        .font(.system(size: 10, weight: .semibold))
                    Text(viewModel.isOnACPower ? "AC Power" : "On Battery")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(viewModel.isOnACPower ? .teal : .green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
                .cornerRadius(20)
                .help(viewModel.isOnACPower ? "Rules run at full speed" : "Rules with battery-saving enabled run at reduced speed")

                // Status Badge
                if !viewModel.isAuthorized {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Authorization Required")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(20)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            ScrollView {
                VStack(spacing: 20) {
                    // Temperature Sensors Row
                    HStack(spacing: 10) {
                        TempMetricCard(
                            title: "Battery",
                            temp: viewModel.batteryTemp,
                            iconName: "battery.100.bolt",
                            iconColor: .green,
                            isSelected: selectedSensor == .battery
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if selectedSensor == .battery {
                                    selectedSensor = nil
                                } else {
                                    selectedSensor = .battery
                                }
                            }
                        }
                        .onHover { inside in
                            if inside {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .help("Click to toggle battery temperature history")
                        
                        TempMetricCard(
                            title: "CPU Die",
                            temp: viewModel.cpuTemp,
                            iconName: "cpu",
                            iconColor: .orange,
                            isSelected: selectedSensor == .cpu
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if selectedSensor == .cpu {
                                    selectedSensor = nil
                                } else {
                                    selectedSensor = .cpu
                                }
                            }
                        }
                        .onHover { inside in
                            if inside {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .help("Click to toggle CPU temperature history")
                        
                        TempMetricCard(
                            title: "GPU proximity",
                            temp: viewModel.gpuTemp,
                            iconName: "gauge.with.needle",
                            iconColor: .purple,
                            isSelected: selectedSensor == .gpu
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if selectedSensor == .gpu {
                                    selectedSensor = nil
                                } else {
                                    selectedSensor = .gpu
                                }
                            }
                        }
                        .onHover { inside in
                            if inside {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .help("Click to toggle GPU temperature history")
                    }
                    .padding(.horizontal, 24)
                    
                    if let sensor = selectedSensor {
                        TempHistoryChartView(
                            sensor: sensor,
                            history: viewModel.tempHistory,
                            onClose: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedSensor = nil
                                }
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 24)
                    }
                    
                    // Privilege setup card if helper not authorized
                    if !viewModel.isAuthorized {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.15))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.orange)
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Helper Authentication Required")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Text("SMC (System Management Controller) fan modification requires root privileges. A bundled helper daemon performs these actions safely over an authenticated XPC connection. Click below to install it — you may need to approve it once under System Settings ▸ Login Items.")
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                        .lineSpacing(4)
                                }
                            }
                            
                            if let error = viewModel.errorMessage {
                                Text(error)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.red)
                                    .padding(8)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            
                            Button(action: {
                                withAnimation {
                                    viewModel.authorize()
                                }
                            }) {
                                HStack {
                                    Spacer()
                                    Image(systemName: "key.fill")
                                    Text("Authorize & Enable Fan Adjustments")
                                    Spacer()
                                }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.vertical, 10)
                                .background(Color.orange)
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(20)
                        .background(Color.orange.opacity(0.04))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, 24)
                    }
                    
                    // Global controls panel
                    if viewModel.isAuthorized && !viewModel.fans.isEmpty {
                        VStack(spacing: 16) {
                            HStack {
                                Toggle(isOn: $viewModel.linkedFans) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "link")
                                            .foregroundColor(viewModel.linkedFans ? .teal : .gray)
                                        Text("Sync All Fans Together")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .teal))
                                
                                Spacer()
                                
                                Button(action: {
                                    viewModel.resetAll()
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.counterclockwise")
                                        Text("Reset All to Auto")
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(20)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                        )
                        .padding(.horizontal, 24)
                    }
                    
                    // Fan-operation errors (e.g. an SMC unlock failure) used to be
                    // swallowed here once authorized, since the only error display
                    // lived inside the "Authorization Required" card above, which
                    // stops rendering once isAuthorized is true.
                    if viewModel.isAuthorized, let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                            .padding(.horizontal, 24)
                    }

                    // Fans List
                    if viewModel.fans.isEmpty {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Reading SMC registers...")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .frame(height: 180)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(viewModel.fans) { fan in
                                FanControlRow(fan: fan, viewModel: viewModel)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    if viewModel.isAuthorized && !viewModel.fans.isEmpty {
                        RulesEngineView(viewModel: viewModel)
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 480, idealWidth: 580, maxWidth: .infinity, minHeight: 520, idealHeight: 680, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .background(WindowAccessor { window in
            window.delegate = MainWindowDelegate.shared
        })
    }
}

// MARK: - Window Accessor and Delegate for Menu Bar Mode
struct WindowAccessor: NSViewRepresentable {
    var onWindowBind: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindowBind(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class MainWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = MainWindowDelegate()
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        return false
    }
}
