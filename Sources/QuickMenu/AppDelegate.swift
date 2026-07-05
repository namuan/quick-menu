import Cocoa
import SwiftUI
import Accessibility
import Carbon.HIToolbox
import CoreGraphics

// MARK: - UserDefaults Keys
extension UserDefaults {
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let skipAppleMenuKey = "skipAppleMenu"
    
    var hasCompletedOnboarding: Bool {
        get { bool(forKey: Self.hasCompletedOnboardingKey) }
        set { set(newValue, forKey: Self.hasCompletedOnboardingKey) }
    }
    
    var skipAppleMenu: Bool {
        get { bool(forKey: Self.skipAppleMenuKey) }
        set { set(newValue, forKey: Self.skipAppleMenuKey) }
    }
}

struct SearchableMenuItem {
    let title: String
    let breadcrumb: String
    let path: [Int]
    let isEnabled: Bool
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var globalHotkey: EventHotKeyRef?
    var searchWindow: NSPanel?
    var onboardingWindow: NSWindow?
    var currentFrontmostApp: NSRunningApplication?
    var currentMenuSearchIndex: [SearchableMenuItem] = []
    var isTerminating = false
    let maxSearchResults = 50
    let maxActionDispatchAttempts = 4
    let actionDispatchRetryDelay: TimeInterval = 0.08
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("=== QuickMenu Started ===")
        Logger.shared.info("Log file location: \(Logger.shared.logFilePath)")
        Logger.shared.info("Bundle identifier: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        Logger.shared.info("Application finished launching")
        
        if UserDefaults.standard.object(forKey: UserDefaults.skipAppleMenuKey) == nil {
            UserDefaults.standard.skipAppleMenu = true
        }
        
        Logger.shared.info("skipAppleMenu: \(UserDefaults.standard.skipAppleMenu)")
        Logger.shared.info("hasCompletedOnboarding: \(UserDefaults.standard.hasCompletedOnboarding)")
        
        // Prevent app from appearing in the Dock or App Switcher
        // when it has no visible windows (transient agent behavior)
        NSApp.setActivationPolicy(.accessory)
        
        if !UserDefaults.standard.hasCompletedOnboarding {
            Logger.shared.info("First launch — showing onboarding")
            showOnboarding()
        } else {
            Logger.shared.info("Launching directly into search flow")
            launchSearchFlow()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("Application will terminate")
        closeSearchWindow()
        unregisterGlobalHotkey()
        Logger.shared.info("=== QuickMenu Stopped ===")
    }
    
    // MARK: - Onboarding
    
    func showOnboarding() {
        Logger.shared.info("Preparing onboarding window")
        NSApp.setActivationPolicy(.regular)
        
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
        Logger.shared.info("Onboarding completed — proceeding to search flow")
        UserDefaults.standard.hasCompletedOnboarding = true
        onboardingWindow?.close()
        onboardingWindow = nil
        NSApp.setActivationPolicy(.accessory)
        launchSearchFlow()
    }
    
    // MARK: - Single-run search flow
    
    func launchSearchFlow() {
        Logger.shared.info("Starting single-run search flow")
        registerGlobalHotkey()
        
        let hasPermission = checkAccessibilityPermissions(prompt: false)
        if !hasPermission {
            Logger.shared.warning("Accessibility permission missing — prompting user")
            promptForPermission { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    Logger.shared.info("Permission granted after prompt — proceeding")
                    DispatchQueue.main.async { self.performMenuCaptureAndSearch() }
                } else {
                    Logger.shared.info("User declined permission — terminating")
                    self.terminateApp()
                }
            }
            return
        }
        
        Logger.shared.info("Accessibility permission already granted")
        performMenuCaptureAndSearch()
    }
    
    func promptForPermission(completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "QuickMenu needs Accessibility permissions to capture menu items from other applications. Without this permission, the app cannot function."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        
        let response = alert.runModal()
        Logger.shared.info("Permission prompt response: \(response.rawValue)")
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
            // Poll for permission
            pollForPermission(completion: completion)
        } else {
            completion(false)
        }
    }
    
    func pollForPermission(completion: @escaping (Bool) -> Void) {
        var attempts = 0
        let maxAttempts = 60
        
        func check() {
            attempts += 1
            let hasPermission = checkAccessibilityPermissions(prompt: false)
            if hasPermission {
                Logger.shared.info("Permission granted after \(attempts) poll(s)")
                completion(true)
                return
            }
            if attempts >= maxAttempts {
                Logger.shared.warning("Permission polling timed out after \(maxAttempts) attempts")
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: check)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: check)
    }
    
    func performMenuCaptureAndSearch() {
        guard let targetApp = getTargetApplication() else {
            Logger.shared.error("No suitable target application found — failing fast")
            let alert = NSAlert()
            alert.messageText = "No Target Application"
            alert.informativeText = "QuickMenu could not find a suitable application to capture menu items from. Please make sure another app is open and try again."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            terminateApp()
            return
        }
        
        Logger.shared.info("Target application: \(targetApp.localizedName ?? "Unknown") (pid: \(targetApp.processIdentifier))")
        
        let pid = targetApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var menuBarValue: AnyObject?
        let menuBarResult = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue)
        
        guard menuBarResult == .success, let menuBar = menuBarValue else {
            Logger.shared.error("Failed to get menu bar for \(targetApp.localizedName ?? "Unknown"), result: \(menuBarResult)")
            let alert = NSAlert()
            alert.messageText = "Menu Capture Failed"
            alert.informativeText = "QuickMenu could not read the menu bar from \(targetApp.localizedName ?? "the active application"). This app may not expose its menu via Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            terminateApp()
            return
        }
        
        Logger.shared.info("Got menu bar, building menu...")
        
        currentFrontmostApp = targetApp
        
        guard let rebuiltMenu = buildMenu(from: menuBar as! AXUIElement, path: []) else {
            Logger.shared.error("Failed to rebuild menu")
            terminateApp()
            return
        }

        currentMenuSearchIndex = collectSearchableMenuItems(from: rebuiltMenu)
        Logger.shared.info("Indexed \(currentMenuSearchIndex.count) searchable menu entries")

        guard !currentMenuSearchIndex.isEmpty else {
            Logger.shared.warning("No searchable entries found — failing fast")
            let alert = NSAlert()
            alert.messageText = "No Menu Items Found"
            alert.informativeText = "QuickMenu did not find any menu items in \(targetApp.localizedName ?? "the active application"). This app may have an empty or inaccessible menu bar."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            terminateApp()
            return
        }

        Logger.shared.info("Menu built with \(rebuiltMenu.items.count) top-level item(s) — opening instant search")
        showInstantSearchWindow(with: currentMenuSearchIndex)
    }
    
    // MARK: - Self-exclusion: avoid indexing QuickMenu itself
    
    func getTargetApplication() -> NSRunningApplication? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            Logger.shared.warning("No frontmost application found")
            return findAlternativeApplication()
        }
        
        // If QuickMenu itself is the frontmost app, fall back
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            Logger.shared.info("Frontmost app is QuickMenu — finding alternative")
            return findAlternativeApplication()
        }
        
        return frontApp
    }
    
    func findAlternativeApplication() -> NSRunningApplication? {
        let ownBundleID = Bundle.main.bundleIdentifier
        let runningApps = NSWorkspace.shared.runningApplications
        
        // Prefer regular apps that are not QuickMenu
        if let alt = runningApps.first(where: { app in
            app.activationPolicy == .regular &&
            app.bundleIdentifier != ownBundleID
        }) {
            Logger.shared.info("Alternative target: \(alt.localizedName ?? "Unknown")")
            return alt
        }
        
        Logger.shared.warning("No alternative application found")
        return nil
    }
    

    
    // MARK: - Accessibility Permissions
    
    @discardableResult
    func checkAccessibilityPermissions(prompt: Bool = true) -> Bool {
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let hasPermission = AXIsProcessTrustedWithOptions(options)
        Logger.shared.debug("Accessibility permission check (prompt=\(prompt)) returned \(hasPermission)")
        return hasPermission
    }
    
    @objc func openAccessibilitySettings() {
        Logger.shared.info("Opening macOS Accessibility settings")
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                Logger.shared.warning("Using fallback system settings URL")
                NSWorkspace.shared.open(url)
            }
            return
        }
        NSWorkspace.shared.open(url)
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
            if self.searchWindow != nil {
                Logger.shared.info("Closing search dialog via hotkey")
                self.closeSearchWindow()
            } else {
                Logger.shared.info("Re-opening search dialog via hotkey")
                self.performMenuCaptureAndSearch()
            }
        }
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
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .windowBackgroundColor

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
                // Dismiss the search window without terminating (termination happens after action executes)
                if let window = self.searchWindow {
                    window.orderOut(nil)
                    window.close()
                    self.searchWindow = nil
                }
                self.executeMenuItem(path: selected.path, title: selected.title)
            },
            onClose: { [weak self] in
                Logger.shared.info("Instant search closed")
                self?.closeSearchWindow()
            }
        )

        panel.contentView = NSHostingView(rootView: searchView)
    applyHaloEffect(to: panel)
        positionSearchWindow(panel, size: panelSize)

        searchWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Logger.shared.info("Instant search window displayed")
    }

    func applyHaloEffect(to panel: NSPanel) {
        guard let contentView = panel.contentView else {
            return
        }

        contentView.wantsLayer = true
        guard let layer = contentView.layer else {
            return
        }

        let cornerRadius: CGFloat = 10
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = false
        layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer.borderWidth = 1
        layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
        layer.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 14
        layer.shadowOffset = .zero
        Logger.shared.debug("Applied halo styling to instant search panel")
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
        
        // In single-run mode, closing the search dialog terminates the app
        terminateApp()
    }

    func executeMenuItem(path: [Int], title: String) {
        let proxyItem = NSMenuItem(title: title, action: #selector(menuItemSelected(_:)), keyEquivalent: "")
        proxyItem.representedObject = path
        proxyItem.tag = 0 // tag 0 means close and quit after execution
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
        let didActivate = targetApp.activate(options: [.activateIgnoringOtherApps])
        Logger.shared.info("Target activation request result: \(didActivate)")
        executeMenuItemAction(path: path, title: sender.title, targetApp: targetApp, attempt: 1) { [weak self] in
            // Terminate only after the action dispatch completes (success or exhausted retries)
            Logger.shared.info("Action dispatch finished — terminating")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.terminateApp()
            }
        }
        
        Logger.shared.info("menuItemSelected dispatched")
    }

    func executeMenuItemAction(path: [Int], title: String, targetApp: NSRunningApplication, attempt: Int, completion: @escaping () -> Void) {
        let pid = targetApp.processIdentifier
        if !targetApp.isActive {
            let didActivate = targetApp.activate(options: [.activateIgnoringOtherApps])
            Logger.shared.warning("Target app not active on attempt \(attempt); activation requested=\(didActivate)")
            scheduleMenuItemRetry(path: path, title: title, targetApp: targetApp, attempt: attempt, reason: "Target app is not active yet", completion: completion)
            return
        }

        guard let targetElement = resolveMenuElement(path: path, pid: pid) else {
            scheduleMenuItemRetry(path: path, title: title, targetApp: targetApp, attempt: attempt, reason: "Could not resolve menu element", completion: completion)
            return
        }

        let pressResult = AXUIElementPerformAction(targetElement, kAXPressAction as CFString)
        if pressResult == .success {
            Logger.shared.info("Action performed successfully on attempt \(attempt) with AXPress")
            completion()
            return
        }

        Logger.shared.warning("AXPress failed on attempt \(attempt) for '\(title)' with result \(pressResult)")
        let pickResult = AXUIElementPerformAction(targetElement, kAXPickAction as CFString)
        if pickResult == .success {
            Logger.shared.info("Action performed successfully on attempt \(attempt) with AXPick")
            completion()
            return
        }

        if performMenuItemShortcutFallback(for: targetElement, title: title, targetApp: targetApp, attempt: attempt) {
            completion()
            return
        }

        scheduleMenuItemRetry(path: path, title: title, targetApp: targetApp, attempt: attempt, reason: "AXPress=\(pressResult), AXPick=\(pickResult), shortcut fallback unavailable", completion: completion)
    }

    func resolveMenuElement(path: [Int], pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)

        var menuBarValue: AnyObject?
        let menuBarResult = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue)
        guard menuBarResult == .success,
              menuBarValue != nil else {
            Logger.shared.error("Failed to get menu bar for pid \(pid), result: \(menuBarResult)")
            return nil
        }
        let menuBar = menuBarValue as! AXUIElement

        var currentElement: AXUIElement = menuBar
        for index in path {
            var childrenValue: AnyObject?
            let childrenResult = AXUIElementCopyAttributeValue(currentElement, kAXChildrenAttribute as CFString, &childrenValue)

            guard childrenResult == .success,
                  let children = childrenValue as? [AXUIElement],
                  index < children.count else {
                Logger.shared.error("Failed to navigate path \(path) at index \(index), result: \(childrenResult)")
                return nil
            }

            currentElement = children[index]
        }

        return currentElement
    }

    func performMenuItemShortcutFallback(for element: AXUIElement, title: String, targetApp: NSRunningApplication, attempt: Int) -> Bool {
        guard targetApp.isActive else {
            Logger.shared.warning("Cannot send shortcut for '\(title)' on attempt \(attempt): target app not active")
            return false
        }

        guard let keyCode = menuItemCommandKeyCode(for: element) else {
            Logger.shared.warning("No command key equivalent available for '\(title)' on attempt \(attempt)")
            return false
        }

        guard let eventSource = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) else {
            Logger.shared.error("Failed creating keyboard events for shortcut fallback on '\(title)'")
            return false
        }

        let flags = menuItemCommandFlags(for: element)
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.postToPid(targetApp.processIdentifier)
        keyUp.postToPid(targetApp.processIdentifier)
        Logger.shared.info("Action performed successfully on attempt \(attempt) with shortcut fallback")
        return true
    }

    func menuItemCommandKeyCode(for element: AXUIElement) -> CGKeyCode? {
        if let virtualKey = readAXIntAttribute(from: element, attribute: kAXMenuItemCmdVirtualKeyAttribute as CFString) {
            return CGKeyCode(virtualKey)
        }

        guard let commandCharacter = readAXStringAttribute(from: element, attribute: kAXMenuItemCmdCharAttribute as CFString) else {
            return nil
        }

        return keyCode(for: commandCharacter)
    }

    func menuItemCommandFlags(for element: AXUIElement) -> CGEventFlags {
        let rawModifiers = readAXIntAttribute(from: element, attribute: kAXMenuItemCmdModifiersAttribute as CFString) ?? 0
        var flags: CGEventFlags = []

        if rawModifiers & 1 != 0 {
            flags.insert(.maskShift)
        }
        if rawModifiers & 2 != 0 {
            flags.insert(.maskAlternate)
        }
        if rawModifiers & 4 != 0 {
            flags.insert(.maskControl)
        }
        if rawModifiers & 8 == 0 {
            flags.insert(.maskCommand)
        }

        return flags
    }

    func readAXIntAttribute(from element: AXUIElement, attribute: CFString) -> Int? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        return nil
    }

    func readAXStringAttribute(from element: AXUIElement, attribute: CFString) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let stringValue = value as? String,
              !stringValue.isEmpty else {
            return nil
        }

        return stringValue
    }

    func keyCode(for commandCharacter: String) -> CGKeyCode? {
        guard let scalar = commandCharacter.lowercased().unicodeScalars.first else {
            return nil
        }

        switch scalar {
        case "a": return CGKeyCode(kVK_ANSI_A)
        case "b": return CGKeyCode(kVK_ANSI_B)
        case "c": return CGKeyCode(kVK_ANSI_C)
        case "d": return CGKeyCode(kVK_ANSI_D)
        case "e": return CGKeyCode(kVK_ANSI_E)
        case "f": return CGKeyCode(kVK_ANSI_F)
        case "g": return CGKeyCode(kVK_ANSI_G)
        case "h": return CGKeyCode(kVK_ANSI_H)
        case "i": return CGKeyCode(kVK_ANSI_I)
        case "j": return CGKeyCode(kVK_ANSI_J)
        case "k": return CGKeyCode(kVK_ANSI_K)
        case "l": return CGKeyCode(kVK_ANSI_L)
        case "m": return CGKeyCode(kVK_ANSI_M)
        case "n": return CGKeyCode(kVK_ANSI_N)
        case "o": return CGKeyCode(kVK_ANSI_O)
        case "p": return CGKeyCode(kVK_ANSI_P)
        case "q": return CGKeyCode(kVK_ANSI_Q)
        case "r": return CGKeyCode(kVK_ANSI_R)
        case "s": return CGKeyCode(kVK_ANSI_S)
        case "t": return CGKeyCode(kVK_ANSI_T)
        case "u": return CGKeyCode(kVK_ANSI_U)
        case "v": return CGKeyCode(kVK_ANSI_V)
        case "w": return CGKeyCode(kVK_ANSI_W)
        case "x": return CGKeyCode(kVK_ANSI_X)
        case "y": return CGKeyCode(kVK_ANSI_Y)
        case "z": return CGKeyCode(kVK_ANSI_Z)
        case "0": return CGKeyCode(kVK_ANSI_0)
        case "1": return CGKeyCode(kVK_ANSI_1)
        case "2": return CGKeyCode(kVK_ANSI_2)
        case "3": return CGKeyCode(kVK_ANSI_3)
        case "4": return CGKeyCode(kVK_ANSI_4)
        case "5": return CGKeyCode(kVK_ANSI_5)
        case "6": return CGKeyCode(kVK_ANSI_6)
        case "7": return CGKeyCode(kVK_ANSI_7)
        case "8": return CGKeyCode(kVK_ANSI_8)
        case "9": return CGKeyCode(kVK_ANSI_9)
        case ",": return CGKeyCode(kVK_ANSI_Comma)
        case ".": return CGKeyCode(kVK_ANSI_Period)
        case "/": return CGKeyCode(kVK_ANSI_Slash)
        case ";": return CGKeyCode(kVK_ANSI_Semicolon)
        case "'": return CGKeyCode(kVK_ANSI_Quote)
        case "[": return CGKeyCode(kVK_ANSI_LeftBracket)
        case "]": return CGKeyCode(kVK_ANSI_RightBracket)
        case "\\": return CGKeyCode(kVK_ANSI_Backslash)
        case "-": return CGKeyCode(kVK_ANSI_Minus)
        case "=": return CGKeyCode(kVK_ANSI_Equal)
        case "`": return CGKeyCode(kVK_ANSI_Grave)
        default: return nil
        }
    }

    func scheduleMenuItemRetry(path: [Int], title: String, targetApp: NSRunningApplication, attempt: Int, reason: String, completion: @escaping () -> Void) {
        guard attempt < maxActionDispatchAttempts else {
            Logger.shared.error("Giving up action dispatch for '\(title)' after \(attempt) attempt(s). Reason: \(reason)")
            completion()
            return
        }

        let nextAttempt = attempt + 1
        let delay = actionDispatchRetryDelay * Double(attempt)
        Logger.shared.warning("Retrying '\(title)' in \(delay)s (attempt \(nextAttempt)/\(maxActionDispatchAttempts)). Reason: \(reason)")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.executeMenuItemAction(path: path, title: title, targetApp: targetApp, attempt: nextAttempt, completion: completion)
        }
    }
    
    // MARK: - Termination (idempotent, race-resistant)
    
    func terminateApp() {
        guard !isTerminating else {
            Logger.shared.debug("Termination already in progress — ignoring duplicate signal")
            return
        }
        isTerminating = true
        Logger.shared.info("Terminating QuickMenu")
        closeSearchWindowImmediate()
        unregisterGlobalHotkey()
        NSApplication.shared.terminate(nil)
    }
    
    /// Close the search window without triggering terminateApp (used internally during termination)
    func closeSearchWindowImmediate() {
        guard let window = searchWindow else { return }
        window.orderOut(nil)
        window.close()
        searchWindow = nil
        currentMenuSearchIndex = []
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
