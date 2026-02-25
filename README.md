# QuickMenu

QuickMenu is a Swift native macOS application that captures the menu items from the frontmost application and rebuilds them as a popup menu at your current mouse pointer location. This tool enhances productivity by allowing quick access to app menus without navigating to the menu bar.

It leverages macOS's Accessibility API to query and recreate menu structures, making it ideal for users who want seamless menu interactions.

## Features

- **Menu Capture**: Automatically collects menu items from the active application
- **Popup at Cursor**: Displays the rebuilt menu exactly where your mouse is pointing
- **Menu + Submenu Search**: Search across nested menu items and open matching results quickly
- **Toggle with Hotkey**: Open or close instant menu search with Command + Shift + M
- **Actionable Items**: Menu selections trigger the original actions in the source app
- **Onboarding Journey**: Guided setup with permission assistance on first launch
- **Accessibility Integration**: Automatically checks and guides you through enabling permissions
- **Menu Bar Icon**: Quick access via menu bar icon with 🖱️ indicator
- **Rolling File Logs**: Writes logs to `~/Library/Logs/QuickMenu/` with automatic log rotation
- **Lightweight**: Runs as a background agent without a main window
- **Apple Menu Skip**: Option to hide the Apple menu for cleaner menus

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

- Open the popup menu and select **Search Menu Items…** (or press **⌘F** while the menu is open)
- Enter text to search across menu items and nested submenu items
- Select a result to trigger the original menu action

### Logs

- Logs are written to `~/Library/Logs/QuickMenu/`
- Active log file uses app name (`quickmenu.log`) and rotates automatically (`quickmenu.1.log` ... `quickmenu.5.log`)

### Menu Bar

- Click the 🖱️ icon in your menu bar to show the menu
- Access Settings from the menu bar
- Check permission status

### Settings

Access settings via the menu bar or when QuickMenu is running:

- **Skip Apple Menu**: Hide the Apple menu in captured menus
- **Show in Menu Bar**: Toggle the menu bar icon visibility
- **Accessibility Access**: Direct link to system settings

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with macOS Accessibility APIs
- Thanks to the Swift community for resources on AXUIElement
- Inspired by the need for quicker menu access in macOS

## Support

For issues or suggestions, open an [issue](https://github.com/namuan/quick-menu/issues).
