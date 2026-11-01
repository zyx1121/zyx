<div align="center">

<h1>zyx</h1>

<p><strong>A menu bar toolkit for macOS.</strong></p>

[![CI](https://img.shields.io/github/actions/workflow/status/zyx1121/zyx/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/zyx1121/zyx/actions)
[![License](https://img.shields.io/github/license/zyx1121/zyx?style=flat-square)](LICENSE)

**English** | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md)

</div>

zyx puts small tools in one menu bar item. Each tool is one row in the menu.

## Features

- **Open at login**: zyx adds itself to Login Items on first launch. Remove it in System Settings, General, Login Items.
- **Dopamine**: keeps the Mac awake with the lid closed. The switch runs `pmset -a disablesleep 1` and shows the current system setting.

## Quick start

```sh
git clone https://github.com/zyx1121/zyx && cd zyx
scripts/install.sh
```

The first switch asks for your admin password once. zyx then installs a sudoers rule that allows only `pmset -a disablesleep 0` and `1`.

## How it works

- **Read**: each time the menu opens, zyx reads `SleepDisabled` from `pmset -g`.
- **Set**: zyx runs `sudo -n /usr/bin/pmset -a disablesleep <0|1>`.
- **Grant**: without the rule, zyx asks for the password, checks the rule with `visudo -cf` and installs it as `/etc/sudoers.d/zyx`.

To remove the rule, run `sudo rm /etc/sudoers.d/zyx`.

## For AI agents

Facts for coding agents and LLM tools. The rules for changing the code are in [AGENTS.md](AGENTS.md).

- **Summary**: macOS menu bar app with a switch for `pmset disablesleep`.
- **Type**: app
- **Interfaces**: menu bar item
- **Install**: `scripts/install.sh`
- **Run**: `open /Applications/zyx.app`
- **Verify**: `pmset -g | grep SleepDisabled`
- **Config**: none
- **Secrets**: none. The admin password goes to the macOS prompt only.
- **Limits**: macOS 14 or later. Dopamine has no battery or heat guard.

## Development

```sh
swift test
scripts/dev-run.sh
```

CI runs the tests and a universal build on macOS.

## License

[MIT](LICENSE)
