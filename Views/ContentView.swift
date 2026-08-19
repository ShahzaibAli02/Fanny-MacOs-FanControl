import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @ObservedObject var viewModel: FanViewModel
    
    var body: some View {
        GeometryReader { geometry in
            // Available window height, rather than the panel's pixel resolution,
            // determines whether the first screen needs a more compact layout.
            let compactLayout = geometry.size.height < 900
            let horizontalPadding: CGFloat = compactLayout ? 16 : 24

            VStack(spacing: 0) {
            // Title Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Fan Control Center")
                            .font(.system(size: compactLayout ? 18 : 20, weight: .black))
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
            .padding(.horizontal, horizontalPadding)
            .padding(.top, compactLayout ? 16 : 24)
            .padding(.bottom, compactLayout ? 12 : 16)
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            ScrollView {
                VStack(spacing: compactLayout ? 14 : 20) {
                    TempHistoryChartView(history: viewModel.tempHistory, compactLayout: compactLayout)
                        .padding(.horizontal, horizontalPadding)
                        .frame(maxWidth: .infinity)
                    
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
                        .padding(.horizontal, horizontalPadding)
                        .frame(maxWidth: .infinity)
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
                                FanControlRow(
                                    fan: fan,
                                    viewModel: viewModel,
                                    compactLayout: compactLayout
                                )
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .frame(maxWidth: .infinity)
                    }

                    // Preserve the monitoring → manual fans → automatic-rules
                    // reading order, while compact fan cards keep this section
                    // discoverable on lower notebook displays.
                    if viewModel.isAuthorized && !viewModel.fans.isEmpty {
                        RulesEngineView(viewModel: viewModel)
                    }

                    // Secondary application-wide controls follow both the manual
                    // and automatic cooling controls.
                    if viewModel.isAuthorized && !viewModel.fans.isEmpty {
                        VStack(spacing: 16) {
                            HStack {
                                Toggle(isOn: $viewModel.isAutoStart) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "autostartstop")
                                            .foregroundColor(viewModel.isAutoStart ? .teal : .gray)
                                        Text("Start at login (background)")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .teal))
                                .onChange(of: viewModel.isAutoStart) { newValue in
                                    viewModel.toggleAutoStart(newValue)
                                }

                                Spacer()
                            }

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
                        .padding(.horizontal, horizontalPadding)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, compactLayout ? 12 : 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .background(WindowAccessor { window in
            window.delegate = MainWindowDelegate.shared
            window.minSize = NSSize(width: 600, height: 680)
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
        return false
    }
}
