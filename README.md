# macOS Fan Control Utility

A sleek, native SwiftUI macOS application designed for real-time monitoring and manual/automated control of MacBook fan speeds. Compatible with both Intel and Apple Silicon (M1/M2/M3/M4/M5+) architectures.

![macOS Fan Control Center Dashboard](screenshot.png)

It features a dual-component design: a sandboxed SwiftUI GUI front-end that communicates with a privileged command-line helper (`smc-helper`) to securely read and write System Management Controller (SMC) registers.

---

## Features
- **Real-Time RPM Monitor**: Displays actual fan speeds with a custom rotating vector fan blade animation that responds to changes in RPM.
- **Auto-Trigger Rules Engine**: Set custom, automated temperature rules for **CPU**, **GPU**, or **Battery** (e.g., *if CPU ≥ 75°C, override all fans to 80%*). Multiple active rules are evaluated dynamically, prioritizing the highest safety speed, and automatically returning control to macOS once the sensors cool down.
- **Manual Mode Controls**: Precise target speed adjustment sliders.
- **Quick Presets**: Set speed thresholds instantly using the **Min**, **20%**, **50%**, **80%**, or **Max** buttons.
- **Linked Fan Tuning**: Option to sync adjustments across all system fans simultaneously.
- **System Metrics**: Monitors battery and sensor temperatures alongside active speed states.
- **Safety Mode**: Instantly yields control back to macOS automatic management when closed or reset.

---

## 📂 Project Architecture & Code Structure

The codebase is organized into clean, single-responsibility files conforming to MVVM patterns:
*   📂 **`Core/`**: Core drivers (`SMC.swift`) managing the raw AppleSMC register reads/writes and Silicon unlocking sequences.
*   📂 **`Models/`**: Shared structs (`FanJSON.swift`) describing deserialized telemetry packages and auto-rules.
*   📂 **`ViewModels/`**: Orchestration logic (`FanViewModel.swift`) querying sensors, checking authorization, persisting rules, and evaluating automatic triggers.
*   📂 **`Views/`**: Reusable SwiftUI layout pieces.
    *   `SpinningFanView.swift`: Animated vector fan widget.
    *   `TempMetricCard.swift`: Temperature telemetry indicators.
    *   `FanControlRow.swift`: Single-fan state picking and speed slider row.
    *   `RulesEngineView.swift`: Dynamic rules addition board.
    *   `ContentView.swift`: Window layout coordinator.
*   📂 **`App/`**: Application Entry Scene (`FanControlApp.swift`) coordinating regular activation and system Menu Bar Extra tray access.
*   📂 **`Helper/`**: Privilege operations wrapper (`main.swift`) serving as a setuid execution client.

---

## Prerequisites
- **Operating System**: macOS 13.0 Ventura or newer.
- **Build Tools**: Swift compiler (installed via Xcode or Xcode Command Line Tools).

---

## 🛠️ Build and Compilation

Clone the repository and run the automated packager script inside the project directory:

```bash
# Make the build script executable
chmod +x build.sh

# Compile and package the application bundle
./build.sh
```

This compiles `smc-helper` and `FanControl`, drafts the app metadata (`Info.plist`), and processes the visual assets to output a standard application bundle: **`Fan Control.app`**.

---

## 🚀 How to Run the App

1. **Launch the Application**:
   Open the application bundle in Finder or launch it from your terminal:
   ```bash
   open "Fan Control.app"
   ```

2. **Configure Privilege Setup (Required Once)**:
   Writing custom values to the SMC requires administrative permission. On the first launch, follow these steps to configure access:
   - Click the orange **"Authorize & Enable Fan Adjustments"** button in the app window.
   - Enter your macOS administrator password when prompted.
   
   *Alternatively, you can manually set the privileged helper permissions using the command-line:*
   ```bash
   sudo chown root:wheel "Fan Control.app/Contents/MacOS/smc-helper"
   sudo chmod +s "Fan Control.app/Contents/MacOS/smc-helper"
   ```

---

## 🔒 Safety & System Restoration

To return your fans to macOS automatic controller management:
* Select **Auto** in the mode picker for individual fans.
* Click the **"Reset All to Auto"** button at the top/bottom of the window.
* Closing the application will also automatically release manual control overrides.
