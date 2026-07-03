import SwiftUI
import AppKit

// Ensures fan speed overrides are released before the process actually
// exits. Without this, quitting (or Cmd+Q) while a manual/rule override is
// active leaves the SMC pinned at that speed indefinitely, contradicting
// the app's documented "closing releases overrides" safety behavior.
class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: FanViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        viewModel?.resetAllBlocking()
        return .terminateNow
    }
}

@main
struct FanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = FanViewModel()

    init() {
        // Force the app to act as a normal foreground application with dock icon
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(.dark)
                .onAppear {
                    appDelegate.viewModel = viewModel
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        // .contentMinSize lets the window open at the content's ideal size and be
        // freely resized down to the content's minimum, with no upper bound. The
        // previous .contentSize pinned the window to the content's min *and max*;
        // since the root frame's max is .infinity, that made the window mis-size
        // (and fail to track user resizing) instead of letting the content fill it.
        .windowResizability(.contentMinSize)

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
                if let maxSpeed = viewModel.maxFanSpeed {
                    Text("\(maxSpeed) RPM")
                } else {
                    Text("Fan Control")
                }
            }
        }
    }
    
    private func openMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
