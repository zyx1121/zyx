<div align="center">

<h1>zyx</h1>

<p><strong>macOS 菜单栏工具包。</strong></p>

[English](README.md) | [繁體中文](README.zh-TW.md) | **简体中文**

</div>

zyx 把小工具放进同一个菜单栏项目，每个工具是菜单里的一行。

## 功能

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
