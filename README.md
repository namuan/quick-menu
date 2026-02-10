# QuickMenu

QuickMenu is a Swift native macOS application that captures the menu items from the frontmost application and rebuilds them as a popup menu at your current mouse pointer location. This tool enhances productivity by allowing quick access to app menus without navigating to the menu bar.

It leverages macOS's Accessibility API to query and recreate menu structures, making it ideal for users who want seamless menu interactions.

## Features

- **Menu Capture**: Automatically collects menu items from the active application
- **Popup at Cursor**: Displays the rebuilt menu exactly where your mouse is pointing
- **Toggle with Hotkey**: Show or hide the menu with Command + Shift + M
- **Actionable Items**: Menu selections trigger the original actions in the source app
- **Onboarding Journey**: Guided setup with permission assistance on first launch
- **Accessibility Integration**: Automatically checks and guides you through enabling permissions
- **Menu Bar Icon**: Quick access via menu bar icon with 🖱️ indicator
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

3. **Start Using**: Press Command + Shift + M to show the menu at your cursor

## Usage

### Global Hotkey

- **Command + Shift + M**: Toggle the menu at your cursor position
  - Press once to show the menu
  - Press again to hide the menu
  - Works in any application

### Menu Bar

- Click the 🖱️ icon in your menu bar to show the menu
- Access Settings from the menu bar
- Check permission status

### Settings

Access settings via the menu bar or when QuickMenu is running:

- **Skip Apple Menu**: Hide the Apple menu in captured menus
- **Show in Menu Bar**: Toggle the menu bar icon visibility
- **Accessibility Access**: Direct link to system settings

## Development

### Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run
swift run
```

### Project Setup

No Xcode project required - uses Swift Package Manager:

```bash
# Open in Xcode (optional)
open Package.swift
```

### Reset Onboarding

To test the onboarding flow again:

```bash
defaults delete com.namuan.quickmenu hasCompletedOnboarding
```

## Troubleshooting

### Menu doesn't appear

1. Check that Accessibility permissions are granted
2. Look for the 🖱️ icon in the menu bar
3. Try clicking the menu bar icon instead of the hotkey
4. Check Console.app for error messages

### Hotkey not working

- Ensure no other app is using Command + Shift + M
- Try restarting QuickMenu
- Check System Settings > Keyboard > Shortcuts for conflicts

### Permissions issues

1. Remove QuickMenu from System Settings > Privacy & Security > Accessibility
2. Re-add it
3. Restart QuickMenu
4. The onboarding flow will guide you through the process

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with macOS Accessibility APIs
- Thanks to the Swift community for resources on AXUIElement
- Inspired by the need for quicker menu access in macOS

## Support

For issues or suggestions, open an [issue](https://github.com/namuan/quick-menu/issues).

---

**Bundle Identifier**: `com.namuan.quickmenu`  
**Minimum macOS Version**: 13.0 (Ventura)
