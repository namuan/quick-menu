import SwiftUI

struct ContentView: View {
    @State private var hotkeyDescription = "Command + Shift + M"
    @State private var skipAppleMenu = true
    @State private var showInStatusBar = true
    
    var body: some View {
        VStack(spacing: 20) {
            Text("QuickMenu Settings")
                .font(.title)
                .padding(.top)
            
            Form {
                Section(header: Text("Hotkey")) {
                    HStack {
                        Text("Current Hotkey:")
                        Spacer()
                        Text(hotkeyDescription)
                            .fontWeight(.semibold)
                    }
                    
                    Text("Default hotkey is Command + Shift + M")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Menu Options")) {
                    Toggle("Skip Apple Menu", isOn: $skipAppleMenu)
                    Toggle("Show in Status Bar", isOn: $showInStatusBar)
                }
                
                Section(header: Text("Permissions")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accessibility Access")
                                .fontWeight(.medium)
                            Text("Required to capture menu items from other apps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Open System Settings") {
                            Logger.shared.info("Opening Accessibility settings from ContentView")
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            } else {
                                Logger.shared.error("Failed to create Accessibility settings URL in ContentView")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("Usage")
                    .font(.headline)
                
                Text("Press Command + Shift + M to open instant search for the frontmost application. Press it again to close the search dialog.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Spacer()
        }
        .frame(minWidth: 400, minHeight: 450)
        .padding()
        .onAppear {
            Logger.shared.info("ContentView (Settings) appeared")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
