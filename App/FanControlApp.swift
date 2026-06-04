import SwiftUI
import AppKit

@main
struct FanControlApp: App {
    @StateObject private var viewModel = FanViewModel()
    
    init() {
        // Force the app to act as a normal foreground application with dock icon
        NSApplication.shared.setActivationPolicy(.regular)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        
        MenuBarExtra {
            Group {
                ForEach(viewModel.fans) { fan in
                    Button("\(fan.name): \(fan.currentSpeed) RPM (\(fan.mode == 1 ? "Manual" : "Auto"))") {
                        openMainWindow()
                    }
                }
                
                if let battery = viewModel.batteryTemp {
                    Button(String(format: "Battery Temp: %.1f°C", battery)) {
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
                Image(systemName: "wind")
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
