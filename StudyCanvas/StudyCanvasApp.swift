import SwiftUI

@main
struct StudyCanvasApp: App {
    @StateObject var canvasManager = CanvasManager()
    
    init() {
        // Suppress AutoLayout constraint warnings completely
        UserDefaults.standard.setValue(false, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")
        // Disable constraint logging
        if let _ = ProcessInfo.processInfo.environment["UNITTEST"] {
            // Don't suppress in unit tests
        } else {
            // Suppress in normal app runs
            for family in ["", "UILM", "TMIC"] {
                UserDefaults.standard.set(false, forKey: "NS\(family)ConstraintBasedLayoutLogUnsatisfiable")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(canvasManager)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // Save all canvas data before app terminates
                    canvasManager.saveAllStates()
                }
        }
        .windowStyle(.hiddenTitleBar)
        
        Settings {
            SettingsView()
                .environmentObject(canvasManager)
        }
    }
}
