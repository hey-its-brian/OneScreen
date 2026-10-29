# OneScreen

A tiny macOS menu bar app for people who share a monitor between two computers.

When the second monitor is switched to another input (a work laptop, a console), the
Mac still believes the display is attached, so windows keep landing on a screen you
cannot see. OneScreen puts the fix one click away: tell the Mac it has **one screen**
while you work elsewhere, then go back to **two screens** when you return. No trip to
System Settings each time.

## What it does

- Menu bar icon shows the current state: two monitors (extended) or one (single screen).
- **Use One Screen / Use Two Screens** toggles between them.
- **One Screen Means** picks how a single screen is achieved:
  - *Mirror onto the main display* (default): the public Core Graphics mirroring API,
    the same thing as turning on mirroring in System Settings.
  - *Turn the second display off*: the display is disabled entirely, so the main
    display keeps its own resolution and arrangement. This uses the private
    `CGSConfigureDisplayEnabled` call (the same one displayplacer uses); the app
    falls back to mirroring only if that symbol ever disappears.
- Lists the connected displays with their role (main, left of main, mirroring) and size.
- **Launch at Login** via `SMAppService`.
- URL scheme for automation: `onescreen://one`, `onescreen://two`, `onescreen://toggle`.
  Works from Shortcuts, Raycast, a hotkey tool, or the terminal:

  ```bash
  open onescreen://toggle
  ```

The app only ever acts on displays that are **not** the main display, so it cannot
blank the screen you are looking at.

## Build

Requires Xcode and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
scripts/build.sh
```

The app lands at `build/Build/Products/Release/OneScreen.app`. Copy it to
`/Applications` and open it. `scripts/release.sh` produces a Developer ID signed and
notarized zip (see the comments in that script for the one-time notary setup).

Icon: `swift Icon/render.swift --appiconset App/Assets.xcassets/AppIcon.appiconset`.

## How it works

`DisplayController` reads the layout with `CGGetOnlineDisplayList`, `CGDisplayIsMain`,
`CGDisplayIsActive` and `CGDisplayMirrorsDisplay`, and listens to
`CGDisplayRegisterReconfigurationCallback` so the menu follows changes made anywhere
else (System Settings, a replug). Changes are made inside a
`CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration(.permanently)`
transaction.

### The one gotcha

A display that has been turned off with `CGSConfigureDisplayEnabled(false)` vanishes
from every Core Graphics list, including the online list. The only handle left to
turn it back on is its `CGDirectDisplayID`, so OneScreen stores the IDs it disabled in
`UserDefaults` (`disabledDisplayIDs`) and re-enables them from there. If that record is
ever lost (for example the preferences file is deleted while the display is off), the
**Look for Hidden Displays** item tries the plausible IDs one by one; IDs that do not
exist simply fail and are ignored. System Settings > Displays also still works.

## Preferences

Stored under `com.heyitsbrian.onescreen`:

| Key | Meaning |
| --- | --- |
| `oneScreenMethod` | `mirror` or `turnOff` |
| `disabledDisplayIDs` | IDs this app turned off and will turn back on |
| `displayNames` | Cached names so a mirrored or hidden display still shows its name |

## License

MIT
