import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0
    @State private var hasAccessibilityPermission = false
    @State private var isCheckingPermission = false
    
    let totalSteps = 3
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)
            
            // Content based on current step
            Group {
                switch currentStep {
                case 0:
                    welcomeView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 1:
                    permissionsView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 2:
                    completionView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                default:
                    EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            .frame(maxHeight: .infinity)
            
            // Bottom buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        Logger.shared.info("Onboarding back tapped from step \(currentStep)")
                        withAnimation {
                            currentStep -= 1
                        }
                        Logger.shared.info("Onboarding moved to step \(currentStep)")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    if currentStep < totalSteps - 1 {
                        Logger.shared.info("Onboarding continue tapped on step \(currentStep)")
                        withAnimation {
                            currentStep += 1
                        }
                        Logger.shared.info("Onboarding moved to step \(currentStep)")
                    } else {
                        Logger.shared.info("Onboarding completed from final step")
                        isPresented = false
                    }
                }) {
                    HStack {
                        Text(currentStep == totalSteps - 1 ? "Get Started" : "Continue")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(currentStep == 1 && !hasAccessibilityPermission)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .frame(width: 560, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            Logger.shared.info("OnboardingView appeared")
            checkPermission()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if currentStep == 1 && !hasAccessibilityPermission {
                Logger.shared.debug("Onboarding polling accessibility permission")
                checkPermission()
            }
        }
    }
    
    // MARK: - Welcome View
    var welcomeView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
                .symbolRenderingMode(.hierarchical)
            
            Text("Welcome to QuickMenu")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Search and run any app's menu command instantly. No more reaching for the menu bar.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "keyboard", title: "Global Hotkey", description: "Press ⌘⇧M to open instant search")
                FeatureRow(icon: "magnifyingglass", title: "Instant Search", description: "Type to filter menu and submenu items")
                FeatureRow(icon: "checkmark.shield", title: "Full Control", description: "Works with all menu items and shortcuts")
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - Permissions View
    var permissionsView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: hasAccessibilityPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(hasAccessibilityPermission ? .green : .orange)
                .symbolRenderingMode(.hierarchical)
            
            Text("Enable Accessibility Access")
                .font(.title)
                .fontWeight(.bold)
            
            Text("QuickMenu needs Accessibility permissions to read and interact with menu items from other applications.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            VStack(spacing: 16) {
                if hasAccessibilityPermission {
                    permissionGrantedView
                } else {
                    permissionRequiredView
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    var permissionRequiredView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("How to enable:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    instructionStep(number: 1, text: "Click the button below to open System Settings")
                    instructionStep(number: 2, text: "Find 'QuickMenu' in the list")
                    instructionStep(number: 3, text: "Toggle the switch to enable it")
                    instructionStep(number: 4, text: "Return to this window")
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            
            Button(action: {
                Logger.shared.info("Onboarding requested opening Accessibility settings")
                openAccessibilitySettings()
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Open System Settings")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .buttonStyle(BorderedProminentButtonStyle())
            .controlSize(.large)
        }
    }
    
    var permissionGrantedView: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Access Granted")
                        .font(.headline)
                    Text("You're all set to use QuickMenu!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Completion View
    var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "hands.sparkles.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
                .symbolRenderingMode(.hierarchical)
            
            Text("You're Ready!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("QuickMenu is now running in your status bar. Here's how to use it:")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Text("⌘⇧")
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Command + Shift + M")
                            .font(.headline)
                        Text("Open or close instant menu search")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Status Bar Icon")
                            .font(.headline)
                        Text("Open search from the status bar menu")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 16) {
                    Text("⚙️")
                        .font(.system(size: 24))
                        .frame(width: 40, height: 40)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings")
                            .font(.headline)
                        Text("Access settings from the status bar menu")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - Helper Views
    func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .cornerRadius(10)
            
            Text(text)
                .font(.body)
            
            Spacer()
        }
    }
    
    // MARK: - Helper Methods
    func checkPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let previousValue = hasAccessibilityPermission
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)

        if previousValue != hasAccessibilityPermission {
            Logger.shared.info("Onboarding permission state changed to \(hasAccessibilityPermission)")
        }
    }
    
    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            Logger.shared.error("Failed to create Accessibility settings URL from onboarding")
            return
        }
        Logger.shared.info("Opening Accessibility settings from onboarding")
        NSWorkspace.shared.open(url)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(isPresented: .constant(true))
    }
}
