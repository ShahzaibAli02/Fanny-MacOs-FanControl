import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @ObservedObject var viewModel: FanViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Title Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Fan Control Center")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.white)
                        
                        Text("v1.0")
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
                    HStack(spacing: 16) {
                        TempMetricCard(title: "Battery", temp: viewModel.batteryTemp, iconName: "battery.100.bolt", iconColor: .green)
                        TempMetricCard(title: "CPU Die", temp: viewModel.cpuTemp, iconName: "cpu", iconColor: .orange)
                        TempMetricCard(title: "GPU proximity", temp: viewModel.gpuTemp, iconName: "gauge.with.needle", iconColor: .purple)
                    }
                    .padding(.horizontal, 24)
                    
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
                                    
                                    Text("SMC (System Management Controller) fan modification requires root privileges. A local helper tool is bundled to perform these actions safely. Click below to authorize it (requires administrator password once).")
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
        .frame(width: 580, height: 680)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }
}
