# AGENTS.md

## Layout

- `Sources/ZyxKit/Dopamine.swift`: reads and sets `pmset disablesleep`, and installs the sudoers rule.
- `Sources/Zyx/main.swift`: the menu bar item and its panel, one row per tool. The panel copies the system Wi-Fi and Battery menus: 308 pt wide, right edge on the menu bar item, Liquid Glass (`NSGlassEffectView`; `.menu` material before macOS 26), 16 pt corners, gray hover, and a whole row as the switch.
- `Sources/Zyx/Pond.swift`: the zyx.tw pond as a live wallpaper, one desktop-level window per screen that ignores the mouse; the app feeds the cursor in as pointer moves. `ZYX_POND_FRONT=1` floats it over every window and `ZYX_POND_LOG=1` prints page errors, to debug.
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

## Commits

Conventional Commits.
