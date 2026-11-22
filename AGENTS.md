# AGENTS.md

## Layout

- `Sources/ZyxKit/Dopamine.swift`: reads and sets `pmset disablesleep`, and installs the sudoers rule.
- `Sources/Zyx/main.swift`: the app delegate and `DopamineModel`. zyx has no menu bar item; it lives in the island.
- `Sources/Zyx/Island.swift`: zyx itself, a Dynamic Island on the notch, one borderless panel per notched screen at `.statusBar + 8` (at the status bar level, macOS 27 draws its own notch layer over it). It grows on hover with a spring and a haptic and shows Clawd; a click opens the tools, one row each (a whole row is the switch, blue circle when on), and Quit. It shows a notice when a Claude Code session finishes a turn; a click on the notice selects that tmux pane and brings Ghostty forward. The panel is sized once; only its SwiftUI content animates.
- `Sources/ZyxKit/Notch.swift`, `Clawd.swift`, `Wardrobe.swift`, `Notice.swift`: the notch geometry, Clawd's pixels, Clawd's accessories, and the `zyx://done` URL the hook sends.
- `Sources/Stickd/Stickd.swift`: stick's macOS desktop daemon, vendored from `zyx1121/stick` `macos/stickd.swift` (commit `1e5bfec`) and built in Swift 5 language mode. zyx starts it at launch: HTTP on `127.0.0.1:9877`, every request needs the `X-Fw-Token` header from `~/Library/Application Support/stick/token`. The island peeks while an agent acts, and the Stick row pauses it (the same switch as Ctrl+Option+F12). Do not also run stick's LaunchAgent `tw.zyx.stick`: both bind port 9877.
- `scripts/claude-stop-hook.sh`: the Claude Code Stop hook that sends `zyx://done?pane=…&title=…&message=…&active=…` with `open -g`. Install it under `Stop` in `~/.claude/settings.json`.
- `Resources/`: `Info.plist`, `Logo.svg`, and `AppIcon.icon`, an Icon Composer icon made from the logo. `scripts/bundle.sh` compiles it with `actool` into `Assets.car` (macOS 26 and later, no gray frame) and `AppIcon.icns` (earlier versions).
- `scripts/notarize.sh`: notarizes and staples the app with the notarytool keychain profile `zyx-notary`; `scripts/install.sh` runs it and skips it when the profile is missing.

## Rules

- Read the system setting every time the island opens its tools. Never cache tool state in the app.
- The sudoers rule allows exactly `/usr/bin/pmset -a disablesleep 0` and `1`. Never widen it.
- Check every sudoers file with `visudo -cf` before it lands in `/etc/sudoers.d`.
- Build, test and run on the MacBook. Keep `.build` a symlink outside iCloud: its extended attributes break code signing.
- A new tool is one more row in the island's tools. Keep its logic in `ZyxKit` with tests.

## Verify

```sh
swift test
scripts/dev-run.sh
```

Click the island, switch Dopamine, then check `pmset -g | grep SleepDisabled`.

For the island, move the cursor onto the notch: it grows and Clawd appears. Then send a notice for a tmux pane that is not on screen, and click it:

```sh
printf '%s' '{"last_assistant_message":"Done.","background_tasks":[]}' | TMUX_PANE=%18 scripts/claude-stop-hook.sh
```

For Stick, run a command through the daemon and watch the island peek, then press Ctrl+Option+F12 and check that `status` says `paused yes`:

```sh
curl -s -X POST -H "X-Fw-Token: $(cat ~/Library/Application\ Support/stick/token)" --data status http://127.0.0.1:9877/run
```

A dev build answers `zyx://` only after `lsregister -f .build/dist/zyx.app`.

## Commits

Conventional Commits.
