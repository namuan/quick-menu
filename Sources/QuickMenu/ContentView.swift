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
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
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
                
                Text("Press Command + Shift + M to toggle the menu from the frontmost application at your cursor location. Press it again to hide the menu.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Spacer()
        }
        .frame(minWidth: 400, minHeight: 450)
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
