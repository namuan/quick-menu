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
    var currentMenu: NSMenu?  // Strong reference to prevent deallocation issues
    var currentFrontmostApp: NSRunningApplication?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("=== QuickMenu Started ===")
        Logger.shared.info("Log file location: \(Logger.shared.logFilePath)")
        
        // Set defaults
        if UserDefaults.standard.object(forKey: UserDefaults.showInStatusBarKey) == nil {
            UserDefaults.standard.showInStatusBar = true
        }
        if UserDefaults.standard.object(forKey: UserDefaults.skipAppleMenuKey) == nil {
            UserDefaults.standard.skipAppleMenu = true
        }
        
        Logger.shared.info("showInStatusBar: \(UserDefaults.standard.showInStatusBar)")
        Logger.shared.info("skipAppleMenu: \(UserDefaults.standard.skipAppleMenu)")
        Logger.shared.info("hasCompletedOnboarding: \(UserDefaults.standard.hasCompletedOnboarding)")
        
        // Show onboarding if first launch
        if !UserDefaults.standard.hasCompletedOnboarding {
            Logger.shared.info("Showing onboarding")
            showOnboarding()
        } else {
            Logger.shared.info("Skipping onboarding, setting up directly")
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
        Logger.shared.info("hotkeyPressed called")
        DispatchQueue.main.async {
            Logger.shared.info("Processing hotkey on main thread")
            // Check permissions before triggering
            guard self.checkAccessibilityPermissions(prompt: true) else {
                Logger.shared.warning("Permission check failed")
                return
            }
            
            Logger.shared.info("isMenuVisible: \(self.isMenuVisible)")
            
            // Toggle menu visibility
            if self.isMenuVisible {
                Logger.shared.info("Dismissing menu via hotkey")
                self.dismissMenu()
            } else {
                Logger.shared.info("Triggering menu rebuild via hotkey")
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
        Logger.shared.info("triggerMenuRebuild called")
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            Logger.shared.error("Could not get frontmost application")
            return
        }
        
        Logger.shared.info("Frontmost app: \(frontApp.localizedName ?? "Unknown") (pid: \(frontApp.processIdentifier))")
        
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get the menu bar
        var menuBarValue: AnyObject?
        let menuBarResult = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue)
        
        guard menuBarResult == .success, let menuBar = menuBarValue else {
            Logger.shared.error("Failed to get menu bar for \(frontApp.localizedName ?? "Unknown"), result: \(menuBarResult)")
            return
        }
        
        Logger.shared.info("Got menu bar, building menu...")
        
        // Store current frontmost app for later use
        currentFrontmostApp = frontApp
        
        // Build the menu
        guard let rebuiltMenu = buildMenu(from: menuBar as! AXUIElement, path: []) else {
            Logger.shared.error("Failed to rebuild menu")
            return
        }
        
        // Keep strong reference to prevent autorelease issues
        currentMenu = rebuiltMenu
        
        Logger.shared.info("Menu built with \(rebuiltMenu.items.count) items")
        
        // Get mouse location
        let mouseLocation = NSEvent.mouseLocation
        Logger.shared.info("Mouse location: \(mouseLocation)")
        
        // Use statusItem button to show menu at cursor position
        if let button = statusItem?.button {
            // Convert screen coordinates to button's coordinate system
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? button.frame
            let xOffset = mouseLocation.x - buttonFrame.origin.x
            let yOffset = mouseLocation.y - buttonFrame.origin.y
            
            Logger.shared.info("Showing menu from status bar button with offset: (\(xOffset), \(yOffset))")
            
            // Mark as visible
            isMenuVisible = true
            
            // Show the menu
            rebuiltMenu.popUp(positioning: nil, at: NSPoint(x: xOffset, y: yOffset), in: button)
            
            // Menu dismissed
            isMenuVisible = false
            Logger.shared.info("Menu dismissed")
            
            // Clear menu reference after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.currentMenu = nil
                Logger.shared.info("Menu reference cleared")
            }
        } else {
            Logger.shared.error("No status item button available")
        }
        
        Logger.shared.info("triggerMenuRebuild completed")
    }
    
    func buildMenu(from axElement: AXUIElement, depth: Int = 0, path: [Int] = []) -> NSMenu? {
        Logger.shared.info("buildMenu called with depth: \(depth), path: \(path)")
        
        var childrenValue: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(axElement, kAXChildrenAttribute as CFString, &childrenValue)
        
        guard childrenResult == .success,
              let children = childrenValue as? [AXUIElement],
              !children.isEmpty else {
            Logger.shared.warning("buildMenu: No children found or error: \(childrenResult)")
            return nil
        }
        
        Logger.shared.info("buildMenu: Found \(children.count) children at depth \(depth)")
        
        let menu = NSMenu(title: "")
        let skipAppleMenu = UserDefaults.standard.skipAppleMenu
        var validIndex = 0
        
        for (index, child) in children.enumerated() {
            // Skip Apple menu (first item) if desired
            if depth == 0 && index == 0 && skipAppleMenu {
                Logger.shared.info("buildMenu: Skipping Apple menu")
                continue
            }
            
            // Get title
            var titleValue: AnyObject?
            let titleResult = AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
            let title = (titleValue as? String) ?? ""
            
            Logger.shared.debug("buildMenu: Child \(index) title: '\(title)', titleResult: \(titleResult)")
            
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
            
            Logger.shared.debug("buildMenu: Adding menu item '\(title)'")
            
            let item = NSMenuItem(title: title, action: #selector(menuItemSelected(_:)), keyEquivalent: "")
            item.target = self
            // Store the path to this menu item instead of the AXUIElement
            let itemPath = path + [validIndex]
            item.representedObject = itemPath
            item.isEnabled = isEnabled
            
            // Recursively build submenu
            if let submenu = buildMenu(from: child, depth: depth + 1, path: itemPath) {
                item.submenu = submenu
            }
            
            menu.addItem(item)
            validIndex += 1
        }
        
        Logger.shared.info("buildMenu: Created menu with \(menu.items.count) items at depth \(depth)")
        return menu.items.isEmpty ? nil : menu
    }
    
    @objc func menuItemSelected(_ sender: NSMenuItem) {
        Logger.shared.info("menuItemSelected called for: \(sender.title)")
        
        guard let path = sender.representedObject as? [Int] else {
            Logger.shared.error("No path associated with menu item: \(sender.title)")
            return
        }
        
        Logger.shared.info("Menu item path: \(path)")
        
        // Re-query the AX element using the path
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            Logger.shared.error("Could not get frontmost application")
            return
        }
        
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get the menu bar
        var menuBarValue: AnyObject?
        let menuBarResult = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue)
        
        guard menuBarResult == .success, menuBarValue != nil else {
            Logger.shared.error("Failed to get menu bar")
            return
        }
        
        let menuBar = menuBarValue as! AXUIElement
        
        // Navigate to the menu item using the path
        var currentElement: AXUIElement = menuBar
        let skipAppleMenu = UserDefaults.standard.skipAppleMenu
        var adjustedPath = path
        
        // Adjust path if we're skipping Apple menu
        if skipAppleMenu && !path.isEmpty && path[0] > 0 {
            adjustedPath[0] += 1
        }
        
        for index in adjustedPath {
            var childrenValue: AnyObject?
            let result = AXUIElementCopyAttributeValue(currentElement, kAXChildrenAttribute as CFString, &childrenValue)
            
            guard result == .success,
                  let children = childrenValue as? [AXUIElement],
                  index < children.count else {
                Logger.shared.error("Failed to navigate to menu item at index \(index)")
                return
            }
            
            currentElement = children[index]
        }
        
        Logger.shared.info("Found AX element for menu item, performing action with delay")
        
        // Perform the action with a delay to ensure menu is closed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard self != nil else {
                Logger.shared.error("Self was nil when performing action")
                return
            }
            
            Logger.shared.info("Performing AXPressAction...")
            let result = AXUIElementPerformAction(currentElement, kAXPressAction as CFString)
            
            if result == .success {
                Logger.shared.info("Action performed successfully")
            } else {
                Logger.shared.error("Failed to perform action: \(result)")
            }
        }
        
        Logger.shared.info("menuItemSelected completed")
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
