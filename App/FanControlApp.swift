import SwiftUI
import AppKit

@main
struct FanControlApp: App {
    @StateObject private var viewModel = FanViewModel()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // A foreground app owns a persistent Dock icon. Using `.accessory` hid the
        // application from the Dock and made it difficult to bring back to the front.
        NSApplication.shared.setActivationPolicy(.regular)

        // The build keeps a PNG fallback in the bundle. This gives the Dock a custom
        // icon even when an `.icns` conversion is unavailable on the build machine.
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
                }
                .onChange(of: scenePhase) { newPhase in
                    viewModel.setAppActive(newPhase == .active)
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        // macOS constrains this to the usable display automatically. A taller
        // default gives the first window enough room to reveal auto controls.
        .defaultSize(width: 960, height: 900)
        
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
