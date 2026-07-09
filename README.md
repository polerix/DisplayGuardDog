# Display Watchdog Toggle

A macOS menu bar app that watches your multi-monitor arrangement and puts it
back the way you like it when something knocks it out of place — a KVM
switch, a sleep/wake cycle, a display briefly dropping out. Comes with a
hand-drawn pixel-art dog icon that stands when the watchdog is on and
naps when it's off.

## How it works

A small background daemon (`display-watchdog.sh`, installed as a
LaunchAgent) polls your display arrangement every few seconds via
[`displayplacer`](https://github.com/jakehilborn/displayplacer). If it
detects a change that persists across a couple of polls (a debounce, so a
single glitchy read doesn't trigger anything) and enough time has passed
since the last restore attempt (a cooldown, so it doesn't fight you if
you're deliberately rearranging things), it reapplies your last-saved
layout.

The menu bar app is a thin, separate control surface for that daemon — it
doesn't do the watching itself. It toggles the LaunchAgent on/off, lets you
update what "correct" means, and surfaces what the daemon has been doing.

## Features

- **Menu bar toggle** for the watchdog LaunchAgent, with a live icon (standing dog = on, sleeping dog = off).
- **Update Saved Layout** — captures your current arrangement as the new protected baseline. Shows a confirmation with the detected display count first, and escalates to a warning if fewer displays are detected than were previously saved (usually means one's disconnected — an easy way to accidentally save a broken layout without this check).
- **Restore Layout Now** — applies the saved layout immediately, without waiting for the daemon's poll cycle.
- **Restore notifications** — a native notification whenever the daemon actually detects a change and restores (or fails to restore) your layout, so you have visibility into whether it's doing anything.
- **Launch at Login** toggle, right from the menu.
- Warns you if `displayplacer` isn't installed instead of silently enabling a LaunchAgent that's doomed to fail.
- Guards against accidentally running two copies of itself (no duplicate menu bar icons).

## Requirements

- macOS 13 or later.
- [Homebrew](https://brew.sh) + [`displayplacer`](https://github.com/jakehilborn/displayplacer) (`brew install displayplacer`) — does the actual display arrangement work.
- Xcode Command Line Tools (`xcode-select --install`) — needed only to build from source; there's no separate release binary.

## Install

```
git clone <this repo>
cd DisplayWatchdogToggle
./install.sh
```

`install.sh` checks for the Swift toolchain and `displayplacer` (offering to
install the latter via Homebrew if it's missing and Homebrew is present),
builds the app, installs it to `~/Applications`, and installs/updates the
LaunchAgent to point at the scripts bundled inside the app — nothing is
installed outside the app bundle and `~/Library/LaunchAgents`. It's safe to
re-run to upgrade: your saved layout, state, and log in
`~/.display-manager` are never touched by the installer.

### Gatekeeper (unsigned build)

This isn't code-signed or notarized. The first time you open it, macOS will
likely refuse with an "unidentified developer" warning. Either:

- Right-click (or Control-click) the app in Finder → **Open** → **Open** again in the dialog, or
- Run: `xattr -d com.apple.quarantine ~/Applications/DisplayWatchdogToggle.app`

## Uninstall

```
./uninstall.sh
```

Stops and removes the LaunchAgent and the app. You'll be asked separately
whether to also delete `~/.display-manager` (your saved layout/state/log) —
it's kept by default in case you reinstall later.

If you had **Launch at Login** enabled, turn it off from the app's menu
*before* uninstalling — there's no reliable way to unregister that login
item once the app bundle is gone.

## Menu reference

| Item | What it does |
|---|---|
| Update Saved Layout | Saves the current display arrangement as the new thing to protect. Shows a count-based confirmation first. |
| Restore Layout Now | Immediately reapplies the saved layout, without waiting for the daemon. |
| Turn On/Off Display Watchdog | Loads/unloads the background LaunchAgent. |
| Launch at Login | Registers/unregisters the app itself as a login item. |
| Quit | Quits the menu bar app (the watchdog LaunchAgent keeps running independently if it's on). |

## Project layout

```
Sources/main.swift       — the menu bar app (AppKit + ServiceManagement + UserNotifications)
Resources/               — Info.plist and the icon artwork, bundled into the .app
Scripts/                 — the watchdog daemon + save/restore helpers, bundled into the .app
build.sh                 — dev-loop rebuild (no LaunchAgent/installer changes)
install.sh / uninstall.sh
```

## License

MIT — see [LICENSE](LICENSE).
