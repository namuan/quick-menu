import SwiftUI
import AppKit

@main
struct QuickMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // QuickMenu is a single-run application with no persistent UI.
        // The AppDelegate manages the entire lifecycle:
        // onboarding → menu capture → search → quit.
        Settings {
            ContentView()
        }
    }
}
