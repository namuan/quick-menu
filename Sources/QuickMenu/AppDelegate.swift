import Cocoa
import SwiftUI
import Accessibility
import Carbon.HIToolbox
import CoreGraphics

// MARK: - UserDefaults Keys
extension UserDefaults {
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let skipAppleMenuKey = "skipAppleMenu"
    static let showInStatusBarKey = "showInStatusBar"
    
    var hasCompletedOnboarding: Bool {
        get { bool(forKey: Self.hasCompletedOnboardingKey) }
        set { set(newValue, forKey: Self.hasCompletedOnboardingKey) }
    }
    
    var skipAppleMenu: Bool {
        get { bool(forKey: Self.skipAppleMenuKey) }
        set { set(newValue, forKey: Self.skipAppleMenuKey) }
    }
    
    var showInStatusBar: Bool {
        get { bool(forKey: Self.showInStatusBarKey) }
        set { set(newValue, forKey: Self.showInStatusBarKey) }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var globalHotkey: EventHotKeyRef?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var permissionCheckTimer: Timer?
    var currentMenuWindow: NSWindow?
    var isMenuVisible = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set defaults
        if UserDefaults.standard.object(forKey: UserDefaults.showInStatusBarKey) == nil {
            UserDefaults.standard.showInStatusBar = true
        }
        if UserDefaults.standard.object(forKey: UserDefaults.skipAppleMenuKey) == nil {
            UserDefaults.standard.skipAppleMenu = true
        }
        
        // Show onboarding if first launch
        if !UserDefaults.standard.hasCompletedOnboarding {
            showOnboarding()
        } else {
            setupAfterOnboarding()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotkey()
        permissionCheckTimer?.invalidate()
    }
    
    // MARK: - Onboarding
    
    func showOnboarding() {
        let onboardingView = OnboardingView(isPresented: Binding(
            get: { self.onboardingWindow != nil },
            set: { if !$0 { self.onboardingCompleted() } }
        ))
        
        onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        onboardingWindow?.title = "Welcome to QuickMenu"
        onboardingWindow?.contentView = NSHostingView(rootView: onboardingView)
        onboardingWindow?.center()
        onboardingWindow?.isReleasedWhenClosed = false
        
        // Prevent closing without completing
        onboardingWindow?.delegate = self
        
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func onboardingCompleted() {
        UserDefaults.standard.hasCompletedOnboarding = true
        onboardingWindow?.close()
        onboardingWindow = nil
        setupAfterOnboarding()
    }
    
    func setupAfterOnboarding() {
        if UserDefaults.standard.showInStatusBar {
            setupStatusBar()
        }
        registerGlobalHotkey()
        
        // Check permissions silently (don't show alert on startup)
        let hasPermission = checkAccessibilityPermissions(prompt: false)
        if !hasPermission {
            // Show a gentle reminder after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.showPermissionReminder()
            }
        }
    }
    
    // MARK: - Status Bar
    
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.title = "🖱️"
            button.action = #selector(statusBarClicked)
            button.target = self
        }
        
        updateStatusBarMenu()
    }
    
    func updateStatusBarMenu() {
        let menu = NSMenu()
        
        // Show current permission status
        let hasPermission = checkAccessibilityPermissions(prompt: false)
        if !hasPermission {
            let warningItem = NSMenuItem(
                title: "⚠️ Accessibility Access Required",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warningItem.target = self
            menu.addItem(warningItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        menu.addItem(NSMenuItem(title: "Show Menu at Cursor", action: #selector(triggerMenuRebuild), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc func statusBarClicked() {
        // Check permissions first
        if !checkAccessibilityPermissions(prompt: true) {
            return
        }
        triggerMenuRebuild()
    }
    
    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "QuickMenu Settings"
            settingsWindow?.contentView = NSHostingView(rootView: ContentView())
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Accessibility Permissions
    
    @discardableResult
    func checkAccessibilityPermissions(prompt: Bool = true) -> Bool {
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let hasPermission = AXIsProcessTrustedWithOptions(options)
        
        if !hasPermission && prompt {
            showPermissionDeniedAlert()
        }
        
        return hasPermission
    }
    
    func showPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "QuickMenu needs Accessibility permissions to capture menu items from other applications. Without this permission, the app cannot function."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
    
    func showPermissionReminder() {
        let alert = NSAlert()
        alert.messageText = "Enable Accessibility Access"
        alert.informativeText = "QuickMenu works best with Accessibility permissions enabled. This allows it to capture and display menus from other apps. Would you like to enable it now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Remind Me Later")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
    
    @objc func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            // Fallback to general security settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        NSWorkspace.shared.open(url)
        
        // Start monitoring for permission changes
        startPermissionCheckTimer()
    }
    
    func startPermissionCheckTimer() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let hasPermission = self.checkAccessibilityPermissions(prompt: false)
            if hasPermission {
                DispatchQueue.main.async {
                    self.permissionGrantedNotification()
                }
                self.permissionCheckTimer?.invalidate()
                self.permissionCheckTimer = nil
            }
        }
    }
    
    func permissionGrantedNotification() {
        // Update status bar menu to remove warning
        updateStatusBarMenu()
        
        // Show success notification
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Granted"
        alert.informativeText = "Thank you! QuickMenu now has the permissions it needs. You can start using Command + Shift + M to access menus at your cursor."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it!")
        alert.runModal()
    }
    
    // MARK: - Global Hotkey
    
    func registerGlobalHotkey() {
        // Command + Shift + M
        registerHotkey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | shiftKey))
    }
    
    func unregisterGlobalHotkey() {
        if let hotkey = globalHotkey {
            UnregisterEventHotKey(hotkey)
            globalHotkey = nil
        }
    }
    
    func registerHotkey(keyCode: UInt32, modifiers: UInt32) {
        var gHotkeyID = EventHotKeyID()
        gHotkeyID.id = 1
        gHotkeyID.signature = FourCharCode(bitPattern: Int32(fourCharCode(from: "QMNU")))
        
        let eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        
        let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(),
                           { (_, eventRef, userData) -> OSStatus in
                               guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                               let mySelf = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                               mySelf.hotkeyPressed()
                               return noErr
                           },
                           1, [eventType], ptr, nil)
        
        RegisterEventHotKey(keyCode,
                           modifiers,
                           gHotkeyID,
                           GetApplicationEventTarget(),
                           0,
                           &globalHotkey)
    }
    
    func fourCharCode(from string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
    
    @objc func hotkeyPressed() {
        DispatchQueue.main.async {
            // Check permissions before triggering
            guard self.checkAccessibilityPermissions(prompt: true) else { return }
            
            // Toggle menu visibility
            if self.isMenuVisible {
                self.dismissMenu()
            } else {
                self.triggerMenuRebuild()
            }
        }
    }
    
    func dismissMenu() {
        // If a menu is currently showing, we need to dismiss it
        // Since NSMenu.popUp() is modal, we simulate Escape key to close it
        if isMenuVisible {
            simulateEscapeKey()
        }
        
        currentMenuWindow?.close()
        currentMenuWindow = nil
        isMenuVisible = false
    }
    
    func simulateEscapeKey() {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Create key down event for Escape (key code 53)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true) {
            keyDown.post(tap: .cghidEventTap)
        }
        
        // Create key up event for Escape
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Menu Capture and Rebuild
    
    @objc func triggerMenuRebuild() {
        // Dismiss any existing menu first
        dismissMenu()
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            print("Could not get frontmost application")
            return
        }
        
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get the menu bar
        var menuBarValue: AnyObject?
        let menuBarResult = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue)
        
        guard menuBarResult == .success, let menuBar = menuBarValue else {
            print("Failed to get menu bar for \(frontApp.localizedName ?? "Unknown")")
            return
        }
        
        // Build the menu
        guard let rebuiltMenu = buildMenu(from: menuBar as! AXUIElement) else {
            print("Failed to rebuild menu")
            return
        }
        
        // Show at mouse location
        let mouseLocation = NSEvent.mouseLocation
        
        currentMenuWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                                   styleMask: .borderless,
                                   backing: .buffered,
                                   defer: false)
        currentMenuWindow?.setFrameOrigin(mouseLocation)
        currentMenuWindow?.makeKeyAndOrderFront(nil)
        
        // Track that we're about to show a menu
        isMenuVisible = true
        
        // We need to show the menu on a background thread so the main thread
        // can continue to receive hotkey events
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let window = self.currentMenuWindow else { return }
            
            // Show the menu (this blocks until menu is dismissed)
            DispatchQueue.main.sync {
                rebuiltMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: window.contentView)
            }
            
            // Menu was dismissed - clean up on main thread
            DispatchQueue.main.async {
                self.isMenuVisible = false
                self.currentMenuWindow?.close()
                self.currentMenuWindow = nil
            }
        }
    }
    
    func buildMenu(from axElement: AXUIElement, depth: Int = 0) -> NSMenu? {
        var childrenValue: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(axElement, kAXChildrenAttribute as CFString, &childrenValue)
        
        guard childrenResult == .success,
              let children = childrenValue as? [AXUIElement],
              !children.isEmpty else {
            return nil
        }
        
        let menu = NSMenu(title: "")
        let skipAppleMenu = UserDefaults.standard.skipAppleMenu
        
        for (index, child) in children.enumerated() {
            // Skip Apple menu (first item) if desired
            if depth == 0 && index == 0 && skipAppleMenu {
                continue
            }
            
            // Get title
            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
            let title = (titleValue as? String) ?? ""
            
            // Check if enabled
            var enabledValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabledValue)
            let isEnabled = (enabledValue as? Bool) ?? true
            
            // Handle separators
            if title == "-" || title.isEmpty {
                if title == "-" {
                    menu.addItem(NSMenuItem.separator())
                }
                continue
            }
            
            let item = NSMenuItem(title: title, action: #selector(menuItemSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = child
            item.isEnabled = isEnabled
            
            // Recursively build submenu
            if let submenu = buildMenu(from: child, depth: depth + 1) {
                item.submenu = submenu
            }
            
            menu.addItem(item)
        }
        
        return menu.items.isEmpty ? nil : menu
    }
    
    @objc func menuItemSelected(_ sender: NSMenuItem) {
        guard let axElement = sender.representedObject as! AXUIElement? else {
            print("No AX element associated with menu item")
            return
        }
        
        let result = AXUIElementPerformAction(axElement, kAXPressAction as CFString)
        
        if result != .success {
            print("Failed to perform action: \(result)")
        }
    }
}

// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Prevent closing onboarding window without completing
        if sender == onboardingWindow && !UserDefaults.standard.hasCompletedOnboarding {
            // Show alert that user needs to complete onboarding
            let alert = NSAlert()
            alert.messageText = "Complete Setup"
            alert.informativeText = "Please complete the onboarding process to start using QuickMenu. Accessibility permissions are required for the app to function."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Continue Setup")
            alert.runModal()
            return false
        }
        return true
    }
}
