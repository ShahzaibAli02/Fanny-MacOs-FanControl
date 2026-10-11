import SwiftUI
import AppKit

@main
struct FanControlApp: App {
    @StateObject private var viewModel = FanViewModel()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Keep the app launchable without assuming one activation policy.
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(.dark)
                .onAppear {
                    viewModel.setAppActive(scenePhase == .active)
                    if viewModel.runInAccessoryMode {
                        NSApplication.shared.setActivationPolicy(.accessory)
                    }
                }
                .onChange(of: scenePhase) { newPhase in
                    viewModel.setAppActive(newPhase == .active)
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .defaultSize(width: 960, height: 900)
        
        MenuBarExtra {
            Group {
                ForEach(viewModel.fans) { fan in
                    Button(L10n.format(
                        "%@ — %d RPM (%@)",
                        fan.name,
                        fan.currentSpeed,
                        L10n.text(fan.mode == 1 ? "Manual" : "Auto")
                    )) {
                        openMainWindow()
                    }
                }
                
                if let battery = viewModel.batteryTemp {
                    Button(L10n.format("Battery temperature: %.1f°C", battery)) {
                        openMainWindow()
                    }
                }
                
                Divider()
                
                Button("Open Fan Control Center...") {
                    openMainWindow()
                }
                
                Button("Reset All to Auto") {
                    viewModel.resetAll()
                }
                
                Divider()
                
                Button("Manual: 20% Speed") {
                    viewModel.setAllToPercentage(0.20)
                }
                
                Button("Manual: 40% Speed") {
                    viewModel.setAllToPercentage(0.40)
                }
                
                Button("Manual: 50% Speed") {
                    viewModel.setAllToPercentage(0.50)
                }
                
                Button("Manual: 80% Speed") {
                    viewModel.setAllToPercentage(0.80)
                }
                
                Button("Manual: MAX Speed") {
                    viewModel.setAllToPercentage(1.00)
                }
                
                Divider()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "fanblades")
                if let firstFan = viewModel.fans.first {
                    Text("\(firstFan.currentSpeed) RPM")
                } else {
                    Text("Fan Control")
                }
            }
        }
    }
    
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
