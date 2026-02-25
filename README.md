# QuickMenu

QuickMenu is a Swift native macOS application that captures menu items from the frontmost application and opens an instant search dialog so you can run commands quickly without going to the macOS menu bar.

It leverages macOS's Accessibility API to query and recreate menu structures, making it ideal for users who want seamless menu interactions.

## Features

- **Menu Capture**: Automatically collects menu items from the active application
- **Instant Search Dialog**: Opens directly (no intermediate popup menu)
- **Menu + Submenu Search**: Searches across nested menu items and executes matches quickly
- **Top-Level Defaults**: Shows top-level menu items before you type anything
- **Toggle with Hotkey**: Open or close instant menu search with Command + Shift + M
- **Status Bar Access**: Launch search from the status bar menu
- **Active-Screen Centering**: Opens the search dialog centered on the currently active screen
- **Keyboard Navigation**: Supports Tab/Shift+Tab, arrow keys, Enter, and Esc in search
- **Actionable Items**: Menu selections trigger the original actions in the source app
- **Onboarding Journey**: Guided setup with permission assistance on first launch
- **Accessibility Integration**: Automatically checks and guides you through enabling permissions
- **Rolling File Logs**: Writes logs to `~/Library/Logs/QuickMenu/` with automatic log rotation
- **Lightweight**: Runs as a background agent without a main window
- **Apple Menu Skipped by Default**: Excludes the Apple menu from indexed results by default

## Requirements

- macOS Ventura (13.0) or later
- Xcode 14+ for building (Swift 5.7+)
- Accessibility permissions enabled for the app

## Installation

### Quick Install (Recommended)

```bash
git clone https://github.com/namuan/quick-menu.git
cd quick-menu
./install.command
```

The install script will:
1. Build the application using Swift Package Manager
2. Create the app bundle
3. Sign it with ad-hoc signing
4. Install it to `~/Applications/QuickMenu.app`

Note: each install run resets existing Accessibility approval for `com.namuan.quickmenu` so macOS can prompt again.

### First Launch Setup

1. **Open QuickMenu**: Double-click `~/Applications/QuickMenu.app` or run:
   ```bash
   open ~/Applications/QuickMenu.app
   ```

2. **Grant Accessibility Permissions**: 
   - The onboarding window will guide you through this
   - Or manually go to System Settings > Privacy & Security > Accessibility
   - Enable QuickMenu in the list

3. **Start Using**: Press Command + Shift + M to open instant menu search

## Usage

### Global Hotkey

- **Command + Shift + M**: Toggle instant menu search
   - Press once to open the search dialog
   - Press again to close it
   - Works in any application

### Search Menus

- Press **Command + Shift + M** or use the status bar menu item **Search Menu Items**
- The dialog opens centered on the active screen
- By default, it shows top-level menu items for the frontmost app
- Type to filter across top-level and nested submenu items
- Use keyboard shortcuts in search:
   - `Tab` / `Shift+Tab`: cycle results
   - `↑` / `↓`: move selection
   - `Enter`: execute selected item
   - `Esc`: close search

### Logs

- Logs are written to `~/Library/Logs/QuickMenu/`
- Active log file uses app name (`quickmenu.log`) and rotates automatically (`quickmenu.1.log` ... `quickmenu.5.log`)

### Menu Bar

- Click the QuickMenu status bar icon to open the menu
- Access Settings from the menu bar
- Check permission status

### Settings

Access settings via the menu bar or when QuickMenu is running:

- **Hotkey Display**: Shows the current hotkey
- **Menu Options Section**: Includes controls for skip Apple menu and status bar visibility
- **Accessibility Access**: Direct link to system settings

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with macOS Accessibility APIs
- Thanks to the Swift community for resources on AXUIElement
- Inspired by the need for quicker menu access in macOS

## Support

For issues or suggestions, open an [issue](https://github.com/namuan/quick-menu/issues).
