# SpaceTab

**A fast, Ubuntu-style window switcher for macOS. Free and open source, with every feature included.**

Press <kbd>⌥ Option</kbd> + <kbd>Tab</kbd> to switch between the **windows on your current desktop**, not between apps from every desktop the way <kbd>⌘</kbd> + <kbd>Tab</kbd> does.

> **Status: early development.** The features below are the project's plan. See the [Roadmap](#roadmap) for what is done.

---

## Why SpaceTab?

The built-in <kbd>⌘</kbd> + <kbd>Tab</kbd> in macOS:

- switches between **apps**, not windows
- shows apps from **every desktop (Space)**, so it keeps jumping you to other desktops
- has no window previews, search or settings

SpaceTab works like <kbd>Alt</kbd> + <kbd>Tab</kbd> on Ubuntu and Windows, and shows only the current desktop by default.

**Every feature is free.** Search, all three styles, automatic sizing and up to 9 shortcuts are included for everyone. Other switchers sell some of these as paid extras. SpaceTab never will.

---

## Features

### Switching
- **Current desktop only.** Shows only the windows on the desktop you are on (this can be changed to show all desktops).
- **Window-level switching.** Every window is shown separately, including several windows of the same app.
- **Most recently used order**, like Ubuntu and Windows.
- **Multi-monitor support.** Show windows from the current screen or from all screens.
- **Minimized and hidden windows.** Choose to show them, hide them, or show them at the end of the list.

### Search
- **Search windows.** While the switcher is open, press <kbd>/</kbd> and type to filter windows by app name or window title. The switcher stays open, so you can let go of <kbd>⌥</kbd> while you type.
- **Fuzzy matching**, so `vsc` finds *Visual Studio Code*.

### Shortcuts
- **Up to 9 shortcuts**, each with its own settings. For example:
  - <kbd>⌥</kbd> + <kbd>Tab</kbd>: windows on the current desktop
  - <kbd>⌘</kbd> + <kbd>`</kbd>: windows of the current app only (optional, replaces the macOS shortcut of the same name)
  - <kbd>⌃</kbd> + <kbd>⌥</kbd> + <kbd>Tab</kbd>: windows from all desktops
- **Actions inside the switcher:** close (<kbd>W</kbd>), minimize (<kbd>M</kbd>), quit app (<kbd>Q</kbd>), full screen (<kbd>F</kbd>), hide (<kbd>H</kbd>).
- **Mouse and trackpad support.** Click a window to switch, or hover to select.

### Appearance
- **Three styles:**
  - **Thumbnails:** live previews of every window
  - **App Icons:** a clean, Dock-like row
  - **Titles:** a compact text-only list
- **Thumbnails sized automatically** to fit how many windows you have.
- **Light, dark and system themes.**
- **Adjustable** size, spacing, corner radius, transparency and animation speed.

### Control
- **Blacklist apps** so they never appear in the switcher.
- **Launch at login.**
- **Menu bar icon**, which you can hide.

### Planned for later
- **Import and export settings** to move them to another Mac.
- **Group windows by app.**
- **Translations.**

---

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel Mac

---

## Installation

> Not released yet. These steps are for version 1.0.

**Homebrew**

```bash
brew install --cask muhammad-Osman/tap/spacetab
```

**Manual download**

Download the latest `.dmg` from the [Releases](../../releases) page and drag **SpaceTab** into **Applications**.

---

## Permissions

The first time you open SpaceTab, macOS asks for two permissions:

| Permission | Why it is needed |
|---|---|
| **Accessibility** | To detect <kbd>⌥</kbd> + <kbd>Tab</kbd> in any app and to focus, close or minimize windows |
| **Screen Recording** | To show window thumbnails. Not needed for the App Icons or Titles styles |

Turn both on in **System Settings → Privacy & Security**.

<kbd>⌥</kbd> + <kbd>Tab</kbd> pauses while an app has **secure input** on, for example while you type in a password field or when Terminal's Secure Keyboard Entry is enabled. macOS hides key presses from other apps during that time. The menu bar icon's menu tells you when this happens.

SpaceTab does **not** collect data, has **no analytics** and makes **no network requests** apart from optional update checks.

---

## Default shortcuts

| Keys | Action |
|---|---|
| <kbd>⌥</kbd> + <kbd>Tab</kbd> | Open the switcher / next window |
| <kbd>⌥</kbd> + <kbd>⇧</kbd> + <kbd>Tab</kbd> | Previous window |
| <kbd>←</kbd> <kbd>→</kbd> <kbd>↑</kbd> <kbd>↓</kbd> | Move the selection |
| Release <kbd>⌥</kbd> | Switch to the selected window |
| <kbd>Esc</kbd> | Close without switching |
| <kbd>/</kbd> | Search windows |
| <kbd>W</kbd> / <kbd>M</kbd> / <kbd>Q</kbd> / <kbd>F</kbd> / <kbd>H</kbd> | Close window / minimize / quit app / full screen / hide |

All shortcuts can be changed in **Settings → Controls**.

---

## Building from source

```bash
git clone https://github.com/muhammad-Osman/spacetab.git
cd spacetab
scripts/build-app.sh
open build/SpaceTab.app
```

SpaceTab is a Swift package. To work on it in Xcode, run `open Package.swift`. Run the tests with `swift test`.

Build and run the app with `scripts/build-app.sh`, not from Xcode: Launch at Login and the Accessibility permission need the app bundle.

The script quits a running SpaceTab first, so the next launch runs the new build.

The script signs the app ad hoc, and macOS treats each changed ad hoc build as a new app. When the signature changes, the script resets SpaceTab's Accessibility permission, and you grant it again after opening the new build. To keep the permission across builds, sign with your own certificate: `SIGN_IDENTITY="Apple Development: Your Name" scripts/build-app.sh`. The first build with a certificate needs one last grant. If System Settings shows SpaceTab as allowed but it doesn't work, remove it from the list with the minus button and add it again.

**You need:** Xcode 16 or later and macOS 14 or later.

---

## How it works

| Part | Technology |
|---|---|
| App and UI | Swift, AppKit |
| Global shortcuts | `CGEventTap` |
| Listing and controlling windows | Accessibility API (`AXUIElement`) |
| Windows on the current desktop | `CGWindowListCopyWindowInfo` (on-screen windows) |
| Most recently used order | Accessibility focus notifications (`AXObserver`) |
| Windows on other desktops, minimized windows | Private SkyLight / CGS APIs (planned) |
| Window thumbnails | ScreenCaptureKit |
| Automatic updates | Sparkle |

> **Note:** macOS has no public API for desktops (Spaces), so SpaceTab uses private APIs, like other window managers do. A new macOS version can break them, and fixes are released as quickly as possible. Because of these APIs, SpaceTab cannot be sold on the Mac App Store and is distributed directly instead.

---

## Roadmap

### v0.1: Basic switcher
- [x] Menu bar app with launch at login
- [x] <kbd>⌥</kbd> + <kbd>Tab</kbd> global shortcut
- [x] List the windows on the current desktop
- [x] Most recently used order
- [x] Switch to the selected window
- [x] Titles style

### v0.5: Daily use
- [ ] Thumbnails and App Icons styles
- [ ] Multi-monitor support
- [ ] Minimized and hidden windows
- [ ] Settings window

### v1.0: Public release
- [ ] Search
- [ ] Up to 9 custom shortcuts
- [ ] Close / minimize / quit / full screen / hide actions
- [ ] App blacklist
- [ ] Themes and appearance settings
- [ ] Signed and notarized build
- [ ] Homebrew cask
- [ ] Automatic updates

### Later
- [ ] Import and export of settings
- [ ] Window grouping by app
- [ ] Translations

---

## Contributing

Contributions are welcome.

1. Fork the repository
2. Create a branch: `git checkout -b feature/my-feature`
3. Commit your changes
4. Open a pull request

For bugs, please open an issue with your macOS version, SpaceTab version and steps to reproduce.

---

## Supporting the project

SpaceTab is free, with no paid version and no locked features. Keeping it working with each new macOS release takes time, and signing the app costs money every year. If SpaceTab is useful to you, you can support it through [GitHub Sponsors](https://github.com/sponsors/muhammad-Osman).

---

## License

[MIT](LICENSE). Free to use, change and share.

---

## Acknowledgements

Inspired by Alt+Tab on Ubuntu and Windows, and by the open-source macOS window switchers that came before it, including [AltTab](https://github.com/lwouis/alt-tab-macos).

SpaceTab is written from scratch and contains no code from AltTab, which is licensed under GPL-3.0.
