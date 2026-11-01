<div align="center">

<h1>zyx</h1>

<p><strong>macOS 選單列工具包。</strong></p>

[English](README.md) | **繁體中文** | [简体中文](README.zh-CN.md)

</div>

zyx 把小工具放進同一個選單列項目，每個工具是選單裡的一列。

## 功能

- **開機自動啟動**：第一次開啟時，zyx 會把自己加進登入項目。要關掉，到「系統設定」、「一般」、「登入項目」移除。
- **Dopamine**：闔蓋時讓 Mac 保持清醒。開關會執行 `pmset -a disablesleep 1`，並顯示目前的系統設定。

## 快速開始

```sh
git clone https://github.com/zyx1121/zyx && cd zyx
scripts/install.sh
```

第一次切換會要求輸入一次管理員密碼。之後 zyx 裝一條 sudoers 規則，只允許 `pmset -a disablesleep 0` 與 `1`。

要移除規則，執行 `sudo rm /etc/sudoers.d/zyx`。

## 授權

[MIT](LICENSE)
