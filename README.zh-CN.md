<div align="center">

<h1>zyx</h1>

<p><strong>MacBook 刘海里的工具包。</strong></p>

[English](README.md) | [繁體中文](README.zh-TW.md) | **简体中文**

</div>

zyx 把刘海变成灵动岛。指向刘海它会变大，点一下打开工具，每个工具一行。

## 功能

- **开机自动启动**：第一次打开时，zyx 会把自己加进登录项。要关掉，到「系统设置」、「通用」、「登录项」移除。
- **Claude Code 通知**：tmux 里的 Claude Code 会话完成一轮时，灵动岛会显示它的名字和回复的第 1 行。点通知会跳到那个 tmux 标签页。把 `scripts/claude-stop-hook.sh` 设为 `~/.claude/settings.json` 的 `Stop` hook。
- **Dopamine**：合盖时让 Mac 保持唤醒。开关会执行 `pmset -a disablesleep 1`，并显示当前的系统设置。

## 快速开始

```sh
git clone https://github.com/zyx1121/zyx && cd zyx
scripts/install.sh
```

第一次切换会要求输入一次管理员密码。之后 zyx 安装一条 sudoers 规则，只允许 `pmset -a disablesleep 0` 与 `1`。

要移除规则，执行 `sudo rm /etc/sudoers.d/zyx`。

## 许可

[MIT](LICENSE)
