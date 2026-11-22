<div align="center">

<h1>zyx</h1>

<p><strong>A toolkit in the MacBook notch.</strong></p>

[![CI](https://img.shields.io/github/actions/workflow/status/zyx1121/zyx/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/zyx1121/zyx/actions)
[![License](https://img.shields.io/github/license/zyx1121/zyx?style=flat-square)](LICENSE)

**English** | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md)

</div>

zyx turns the notch into a Dynamic Island. Point at the notch and it grows; click it for the tools, one row each.

## Features

- **Open at login**: zyx adds itself to Login Items on first launch. Remove it in System Settings, General, Login Items.
- **Claude Code notices**: when a Claude Code session in tmux finishes a turn, the island shows its name and the first line of the reply. Click the notice to jump to that tmux tab. Install `scripts/claude-stop-hook.sh` as a `Stop` hook in `~/.claude/settings.json`.
- **Dopamine**: keeps the Mac awake with the lid closed. The switch runs `pmset -a disablesleep 1` and shows the current system setting.
- **Stick**: hosts the desktop daemon of [stick](https://github.com/zyx1121/stick), so agents can see and drive this Mac. The island peeks while an agent acts. The switch, or Ctrl+Option+F12, pauses it.

## Quick start

```sh
git clone https://github.com/zyx1121/zyx && cd zyx
scripts/install.sh
```

The first switch asks for your admin password once. zyx then installs a sudoers rule that allows only `pmset -a disablesleep 0` and `1`.

## How it works

- **Read**: each time the island opens its tools, zyx reads `SleepDisabled` from `pmset -g`.
- **Set**: zyx runs `sudo -n /usr/bin/pmset -a disablesleep <0|1>`.
- **Grant**: without the rule, zyx asks for the password, checks the rule with `visudo -cf` and installs it as `/etc/sudoers.d/zyx`.

To remove the rule, run `sudo rm /etc/sudoers.d/zyx`.

## For AI agents

Facts for coding agents and LLM tools. The rules for changing the code are in [AGENTS.md](AGENTS.md).

- **Summary**: macOS app in the notch, a Dynamic Island with a switch for `pmset disablesleep` and Claude Code notices.
- **Type**: app
- **Interfaces**: the notch island; the `zyx://done` URL scheme
- **Install**: `scripts/install.sh`
- **Run**: `open /Applications/zyx.app`
- **Verify**: `pmset -g | grep SleepDisabled`
- **Config**: none
- **Secrets**: none. The admin password goes to the macOS prompt only.
- **Limits**: macOS 14 or later, a Mac with a notch. Dopamine has no battery or heat guard.

## Development

```sh
swift test
scripts/dev-run.sh
```

CI runs the tests and a universal build on macOS.

## License

[MIT](LICENSE)
