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

struct SearchableMenuItem {
    let title: String
    let breadcrumb: String
    let path: [Int]
    let isEnabled: Bool
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var globalHotkey: EventHotKeyRef?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var permissionCheckTimer: Timer?
    var searchWindow: NSPanel?
    var currentFrontmostApp: NSRunningApplication?
    var currentMenuSearchIndex: [SearchableMenuItem] = []
    let maxSearchResults = 50
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("=== QuickMenu Started ===")
        Logger.shared.info("Log file location: \(Logger.shared.logFilePath)")
        Logger.shared.info("Bundle identifier: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        Logger.shared.info("Application finished launching")
        
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
        Logger.shared.info("Application will terminate")
        closeSearchWindow()
        unregisterGlobalHotkey()
        permissionCheckTimer?.invalidate()
        Logger.shared.info("=== QuickMenu Stopped ===")
    }
    
    // MARK: - Onboarding
    
    func showOnboarding() {
        Logger.shared.info("Preparing onboarding window")
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
        Logger.shared.info("Onboarding window displayed")
    }
    
    func onboardingCompleted() {
        Logger.shared.info("Onboarding completed")
        UserDefaults.standard.hasCompletedOnboarding = true
        onboardingWindow?.close()
        onboardingWindow = nil
        setupAfterOnboarding()
    }
    
    func setupAfterOnboarding() {
        Logger.shared.info("Running post-onboarding setup")
        if UserDefaults.standard.showInStatusBar {
            Logger.shared.info("Status bar is enabled; creating status item")
            setupStatusBar()
        } else {
            Logger.shared.info("Status bar is disabled")
        }
        registerGlobalHotkey()
        
        // Check permissions silently (don't show alert on startup)
        let hasPermission = checkAccessibilityPermissions(prompt: false)
        if !hasPermission {
            Logger.shared.warning("Accessibility permission missing during setup")
            // Show a gentle reminder after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                Logger.shared.info("Showing delayed accessibility reminder")
                self?.showPermissionReminder()
            }
        } else {
            Logger.shared.info("Accessibility permission already granted")
        }
    }
    
    // MARK: - Status Bar
    
    func setupStatusBar() {
        Logger.shared.info("Setting up status bar item")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Use app icon instead of emoji
            if let appIcon = NSImage(named: "AppIcon") {
                let iconSize: CGFloat = 18
                appIcon.size = NSSize(width: iconSize, height: iconSize)
                button.image = appIcon
                button.image?.isTemplate = true
                Logger.shared.debug("Status bar icon configured")
            } else {
                Logger.shared.warning("AppIcon asset not found for status bar")
            }
            button.action = #selector(statusBarClicked)
            button.target = self
            Logger.shared.debug("Status bar button action wired")
        } else {
            Logger.shared.error("Failed to access status bar button")
        }
        
        updateStatusBarMenu()
    }
    
    func updateStatusBarMenu() {
        Logger.shared.info("Refreshing status bar menu")
        let menu = NSMenu()
        
        // Show current permission status
        let hasPermission = checkAccessibilityPermissions(prompt: false)
        if !hasPermission {
            Logger.shared.warning("Status bar menu showing accessibility warning")
            let warningItem = NSMenuItem(
                title: "⚠️ Accessibility Access Required",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warningItem.target = self
            menu.addItem(warningItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        menu.addItem(NSMenuItem(title: "Search Menu Items", action: #selector(triggerMenuRebuild), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        Logger.shared.info("Status bar menu now has \(menu.items.count) items")
    }
    
    @objc func statusBarClicked() {
        Logger.shared.info("Status bar clicked")
        // Check permissions first
        if !checkAccessibilityPermissions(prompt: true) {
            Logger.shared.warning("Status bar click blocked by missing accessibility permission")
            return
        }
        triggerMenuRebuild()
    }
    
    @objc func showSettings() {
        Logger.shared.info("Opening settings window")
        if settingsWindow == nil {
            Logger.shared.debug("Creating settings window")
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
        Logger.shared.info("Settings window visible")
    }
    
    // MARK: - Accessibility Permissions
    
    @discardableResult
    func checkAccessibilityPermissions(prompt: Bool = true) -> Bool {
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let hasPermission = AXIsProcessTrustedWithOptions(options)
        Logger.shared.debug("Accessibility permission check (prompt=\(prompt)) returned \(hasPermission)")
        
        if !hasPermission && prompt {
            showPermissionDeniedAlert()
        }
        
        return hasPermission
    }
    
    func showPermissionDeniedAlert() {
        Logger.shared.warning("Showing permission denied alert")
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "QuickMenu needs Accessibility permissions to capture menu items from other applications. Without this permission, the app cannot function."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        Logger.shared.info("Permission denied alert response: \(response.rawValue)")
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
    
    func showPermissionReminder() {
        Logger.shared.info("Showing permission reminder")
        let alert = NSAlert()
        alert.messageText = "Enable Accessibility Access"
        alert.informativeText = "QuickMenu works best with Accessibility permissions enabled. This allows it to capture and display menus from other apps. Would you like to enable it now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Remind Me Later")
        
        let response = alert.runModal()
        Logger.shared.info("Permission reminder response: \(response.rawValue)")
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
    
    @objc func openAccessibilitySettings() {
        Logger.shared.info("Opening macOS Accessibility settings")
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            // Fallback to general security settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                Logger.shared.warning("Using fallback system settings URL")
                NSWorkspace.shared.open(url)
            }
            return
        }
        NSWorkspace.shared.open(url)
        
        // Start monitoring for permission changes
        startPermissionCheckTimer()
    }
    
    func startPermissionCheckTimer() {
        Logger.shared.info("Starting accessibility permission polling timer")
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let hasPermission = self.checkAccessibilityPermissions(prompt: false)
            if hasPermission {
                Logger.shared.info("Accessibility permission became available")
                DispatchQueue.main.async {
                    self.permissionGrantedNotification()
                }
                self.permissionCheckTimer?.invalidate()
                self.permissionCheckTimer = nil
            }
        }
    }
    
    func permissionGrantedNotification() {
        Logger.shared.info("Showing accessibility granted notification")
        // Update status bar menu to remove warning
        updateStatusBarMenu()
        
        // Show success notification
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Granted"
        alert.informativeText = "Thank you! QuickMenu now has the permissions it needs. You can start using Command + Shift + M to access menus at your cursor."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it!")
        alert.runModal()
        Logger.shared.info("Accessibility granted notification acknowledged")
    }
    
    // MARK: - Global Hotkey
    
    func registerGlobalHotkey() {
        // Command + Shift + M
        Logger.shared.info("Registering global hotkey Command+Shift+M")
        registerHotkey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | shiftKey))
    }
    
    func unregisterGlobalHotkey() {
        if let hotkey = globalHotkey {
            Logger.shared.info("Unregistering global hotkey")
            UnregisterEventHotKey(hotkey)
            globalHotkey = nil
        } else {
            Logger.shared.debug("No global hotkey to unregister")
        }
    }
    
    func registerHotkey(keyCode: UInt32, modifiers: UInt32) {
        Logger.shared.debug("Register hotkey request keyCode=\(keyCode), modifiers=\(modifiers)")
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
        Logger.shared.info("Global hotkey registration finished")
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

            if self.searchWindow != nil {
                Logger.shared.info("Closing search dialog via hotkey")
                self.closeSearchWindow()
            } else {
                Logger.shared.info("Opening search dialog via hotkey")
                self.triggerMenuRebuild()
            }
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

        currentMenuSearchIndex = collectSearchableMenuItems(from: rebuiltMenu)
        Logger.shared.info("Indexed \(currentMenuSearchIndex.count) searchable menu entries")

        guard !currentMenuSearchIndex.isEmpty else {
            Logger.shared.warning("No searchable entries were found")
            return
        }

        Logger.shared.info("Menu built with \(rebuiltMenu.items.count) top-level item(s)")
        Logger.shared.info("Opening instant search directly")
        showInstantSearchWindow(with: currentMenuSearchIndex)
        
        Logger.shared.info("triggerMenuRebuild completed")
    }

    func showInstantSearchWindow(with searchableItems: [SearchableMenuItem]) {
        closeSearchWindow()

        let panelSize = NSSize(width: 700, height: 520)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Search Menu Items"
        panel.identifier = NSUserInterfaceItemIdentifier("InstantSearchPanel")
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .transient]

        let searchView = InstantSearchView(
            maxResults: maxSearchResults,
            defaultItems: searchableItems.filter { $0.path.count == 1 },
            onSearch: { [weak self] query in
                guard let self = self else {
                    return []
                }
                return self.searchMenuItems(query: query, in: searchableItems)
            },
            onSelect: { [weak self] selected in
                guard let self = self else { return }
                Logger.shared.info("Instant search selected: \(selected.breadcrumb)")
                self.closeSearchWindow()
                self.executeMenuItem(path: selected.path, title: selected.title)
            },
            onClose: { [weak self] in
                Logger.shared.info("Instant search closed")
                self?.closeSearchWindow()
            }
        )

        panel.contentView = NSHostingView(rootView: searchView)
        positionSearchWindow(panel, size: panelSize)

        searchWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Logger.shared.info("Instant search window displayed")
    }

    func positionSearchWindow(_ panel: NSPanel, size: NSSize) {
        let activeScreen = currentActiveScreen()
        let targetFrame = activeScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame

        guard let frame = targetFrame else {
            panel.center()
            return
        }

        let origin = NSPoint(
            x: frame.midX - (size.width / 2),
            y: frame.midY - (size.height / 2)
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        Logger.shared.info("Positioned search window centered on active screen")
    }

    func currentActiveScreen() -> NSScreen? {
        if let screen = NSApp.keyWindow?.screen {
            return screen
        }

        if let screen = NSApp.mainWindow?.screen {
            return screen
        }

        if let screen = NSScreen.main {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen
        }

        return NSScreen.screens.first
    }

    func closeSearchWindow() {
        guard let window = searchWindow else {
            return
        }

        window.orderOut(nil)
        window.close()
        searchWindow = nil
        currentMenuSearchIndex = []
        Logger.shared.debug("Search window closed and index cleared")
    }

    func executeMenuItem(path: [Int], title: String) {
        let proxyItem = NSMenuItem(title: title, action: #selector(menuItemSelected(_:)), keyEquivalent: "")
        proxyItem.representedObject = path
        menuItemSelected(proxyItem)
    }

    func collectSearchableMenuItems(from menu: NSMenu, parentTitles: [String] = []) -> [SearchableMenuItem] {
        var results: [SearchableMenuItem] = []

        for item in menu.items {
            if item.isSeparatorItem {
                continue
            }

            if let path = item.representedObject as? [Int], !item.title.isEmpty {
                let breadcrumbParts = parentTitles + [item.title]
                let breadcrumb = breadcrumbParts.joined(separator: " → ")
                results.append(SearchableMenuItem(title: item.title, breadcrumb: breadcrumb, path: path, isEnabled: item.isEnabled))
            }

            if let submenu = item.submenu, !submenu.items.isEmpty {
                let submenuTitle = item.title.isEmpty ? parentTitles : (parentTitles + [item.title])
                results.append(contentsOf: collectSearchableMenuItems(from: submenu, parentTitles: submenuTitle))
            }
        }

        return results
    }

    func searchMenuItems(query: String, in searchableItems: [SearchableMenuItem]) -> [SearchableMenuItem] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = normalizedQuery.split(separator: " ").map(String.init)

        return searchableItems
            .filter { item in
                let haystack = item.breadcrumb.lowercased()
                return terms.allSatisfy { haystack.contains($0) }
            }
            .sorted { lhs, rhs in
                let lhsStartsWith = lhs.title.lowercased().hasPrefix(normalizedQuery)
                let rhsStartsWith = rhs.title.lowercased().hasPrefix(normalizedQuery)

                if lhsStartsWith != rhsStartsWith {
                    return lhsStartsWith && !rhsStartsWith
                }

                if lhs.breadcrumb.count != rhs.breadcrumb.count {
                    return lhs.breadcrumb.count < rhs.breadcrumb.count
                }

                return lhs.breadcrumb.localizedCaseInsensitiveCompare(rhs.breadcrumb) == .orderedAscending
            }
    }

    func appendMenuItems(from sourceMenu: NSMenu, to targetMenu: NSMenu) {
        while let item = sourceMenu.items.first {
            sourceMenu.removeItem(at: 0)
            targetMenu.addItem(item)
        }
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
        
        for (index, child) in children.enumerated() {
            // Skip Apple menu (first item) if desired
            if depth == 0 && index == 0 && skipAppleMenu {
                Logger.shared.info("buildMenu: Skipping Apple menu")
                continue
            }

            let childPath = path + [index]
            
            // Get title
            var titleValue: AnyObject?
            let titleResult = AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
            let rawTitle = (titleValue as? String) ?? ""
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            
            Logger.shared.debug("buildMenu: Child \(index) title: '\(title)', titleResult: \(titleResult)")
            
            // Check if enabled
            var enabledValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabledValue)
            let isEnabled = (enabledValue as? Bool) ?? true
            
            // Handle separators
            if title == "-" {
                menu.addItem(NSMenuItem.separator())
                continue
            }

            if title.isEmpty {
                Logger.shared.debug("buildMenu: Descending into untitled container at path \(childPath)")
                if let nestedMenu = buildMenu(from: child, depth: depth + 1, path: childPath) {
                    Logger.shared.debug("buildMenu: Flattening \(nestedMenu.items.count) nested item(s) from path \(childPath)")
                    appendMenuItems(from: nestedMenu, to: menu)
                }
                continue
            }
            
            Logger.shared.debug("buildMenu: Adding menu item '\(title)'")
            
            let item = NSMenuItem(title: title, action: #selector(menuItemSelected(_:)), keyEquivalent: "")
            item.target = self
            // Store the path to this menu item instead of the AXUIElement
            let itemPath = childPath
            item.representedObject = itemPath
            item.isEnabled = isEnabled
            
            // Recursively build submenu
            if let submenu = buildMenu(from: child, depth: depth + 1, path: itemPath) {
                item.submenu = submenu
            }
            
            menu.addItem(item)
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

        guard let targetApp = currentFrontmostApp ?? NSWorkspace.shared.frontmostApplication else {
            Logger.shared.error("Could not determine target application for menu action")
            return
        }

        Logger.shared.info("Executing action against app: \(targetApp.localizedName ?? "Unknown") (pid: \(targetApp.processIdentifier))")
        targetApp.activate(options: [.activateIgnoringOtherApps])

        let pid = targetApp.processIdentifier
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

        for index in path {
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

struct InstantSearchView: View {
    let maxResults: Int
    let defaultItems: [SearchableMenuItem]
    let onSearch: (String) -> [SearchableMenuItem]
    let onSelect: (SearchableMenuItem) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedIndex: Int?
    @FocusState private var isQueryFocused: Bool

    var matches: [SearchableMenuItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Array(defaultItems.prefix(maxResults))
        }

        return Array(onSearch(trimmed).prefix(maxResults))
    }

    var selectableIndexes: [Int] {
        matches.indices.filter { matches[$0].isEnabled }
    }

    var selectedItem: SearchableMenuItem? {
        guard let selectedIndex,
              matches.indices.contains(selectedIndex) else {
            return nil
        }
        return matches[selectedIndex]
    }

    func moveSelection(forward: Bool) {
        guard !selectableIndexes.isEmpty else {
            selectedIndex = nil
            return
        }

        guard let current = selectedIndex,
              let position = selectableIndexes.firstIndex(of: current) else {
            selectedIndex = selectableIndexes.first
            return
        }

        let nextPosition: Int
        if forward {
            nextPosition = (position + 1) % selectableIndexes.count
        } else {
            nextPosition = (position - 1 + selectableIndexes.count) % selectableIndexes.count
        }

        selectedIndex = selectableIndexes[nextPosition]
    }

    func syncSelectionToMatches() {
        guard !matches.isEmpty else {
            selectedIndex = nil
            return
        }

        if let selectedIndex, matches.indices.contains(selectedIndex), matches[selectedIndex].isEnabled {
            return
        }

        selectedIndex = selectableIndexes.first
    }

    func handleSearchKeyDown(_ event: NSEvent) -> Bool {
        guard event.window?.identifier?.rawValue == "InstantSearchPanel" else {
            return false
        }

        switch event.keyCode {
        case 48: // tab
            guard !matches.isEmpty else {
                return false
            }

            let isReverse = event.modifierFlags.contains(.shift)
            moveSelection(forward: !isReverse)
            return true
        case 125: // down arrow
            moveSelection(forward: true)
            return true
        case 126: // up arrow
            moveSelection(forward: false)
            return true
        case 36, 76: // return / enter
            if let selectedItem {
                onSelect(selectedItem)
                return true
            }
            return false
        case 53: // escape
            onClose()
            return true
        default:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Type to search menu and submenu items", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isQueryFocused)
                .onSubmit {
                    if let selectedItem {
                        onSelect(selectedItem)
                    }
                }

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && matches.isEmpty {
                Text("No top-level menu items found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if matches.isEmpty {
                Text("No matches")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(matches.enumerated()), id: \.offset) { index, item in
                            Button(action: {
                                selectedIndex = index
                                onSelect(item)
                            }) {
                                HStack(spacing: 10) {
                                    Text(item.breadcrumb)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    if index == selectedIndex {
                                        Text("Selected")
                                            .font(.caption2)
                                            .foregroundColor(.accentColor)
                                    }

                                    if !item.isEnabled {
                                        Text("Disabled")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(index == selectedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!item.isEnabled)
                        }
                    }
                }
            }

            HStack {
                Text("\(matches.count) match(es)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Close") {
                    onClose()
                }
            }

            Text("Hints: Type to filter • Tab/Shift+Tab cycle results • ↑/↓ move selection • Enter opens selected • Esc closes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(minWidth: 680, minHeight: 490)
        .onAppear {
            syncSelectionToMatches()
            DispatchQueue.main.async {
                isQueryFocused = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isQueryFocused = true
            }
        }
        .onChange(of: query) { _ in
            syncSelectionToMatches()
        }
        .onChange(of: matches.count) { _ in
            syncSelectionToMatches()
        }
        .background(KeyEventMonitorView(onKeyDown: handleSearchKeyDown))
    }
}

struct KeyEventMonitorView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    class Coordinator {
        var monitor: Any?
        let onKeyDown: (NSEvent) -> Bool

        init(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if context.coordinator.onKeyDown(event) {
                return nil
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
            coordinator.monitor = nil
        }
    }
}
