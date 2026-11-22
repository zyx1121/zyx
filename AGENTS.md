# AGENTS.md

## Layout

- `Sources/ZyxKit/Dopamine.swift`: reads and sets `pmset disablesleep`, and installs the sudoers rule.
- `Sources/Zyx/main.swift`: the menu bar item and its panel, one row per tool. The panel copies the system Wi-Fi and Battery menus: 220 pt wide (narrower than their 308, it holds only short rows), right edge on the menu bar item, Liquid Glass (`NSGlassEffectView`; `.menu` material before macOS 26), 16 pt corners, gray hover, and a whole row as the switch.
- `Sources/Zyx/Pond.swift`: the zyx.tw pond as a live wallpaper, one desktop-level window per screen that ignores the mouse; the app feeds the cursor in as pointer moves. `ZYX_POND_FRONT=1` floats it over every window and `ZYX_POND_LOG=1` prints page errors, to debug.
- `Sources/Zyx/Island.swift`: a Dynamic Island on the notch, one borderless panel per notched screen at `.statusBar + 8` (at the status bar level, macOS 27 draws its own notch layer over it). It grows on hover with a spring and a haptic, shows Clawd, and shows a notice when a Claude Code session finishes a turn; a click on the notice selects that tmux pane and brings Ghostty forward. The panel is sized once; only its SwiftUI content animates.
- `Sources/ZyxKit/Notch.swift`, `Clawd.swift`, `Wardrobe.swift`, `Notice.swift`: the notch geometry, Clawd's pixels, Clawd's accessories, and the `zyx://done` URL the hook sends.
- `scripts/claude-stop-hook.sh`: the Claude Code Stop hook that sends `zyx://done?pane=…&title=…&message=…&active=…` with `open -g`. Install it under `Stop` in `~/.claude/settings.json`.
- `Resources/`: `Info.plist`, `Logo.svg` (source of `AppIcon.icns`), `MenuIcon.pdf` (from zyx1121/cappuccino).

## Rules

- Read the system setting every time the menu opens. Never cache tool state in the app.
- The sudoers rule allows exactly `/usr/bin/pmset -a disablesleep 0` and `1`. Never widen it.
- Check every sudoers file with `visudo -cf` before it lands in `/etc/sudoers.d`.
- Build, test and run on the MacBook. Keep `.build` a symlink outside iCloud: its extended attributes break code signing.
- A new tool is one more row in the menu. Keep its logic in `ZyxKit` with tests.

## Verify

```sh
swift test
scripts/dev-run.sh
```

Open the menu, switch Dopamine, then check `pmset -g | grep SleepDisabled`.

For the island, move the cursor onto the notch: it grows and Clawd appears. Then send a notice for a tmux pane that is not on screen, and click it:

```sh
printf '%s' '{"last_assistant_message":"Done.","background_tasks":[]}' | TMUX_PANE=%18 scripts/claude-stop-hook.sh
```

A dev build answers `zyx://` only after `lsregister -f .build/dist/zyx.app`.

## Commits

Conventional Commits.
