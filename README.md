# ProcreateViewer-Windows-

[English](#english) | [中文](#中文)

---

## English

A lightweight Windows Shell Extension that lets `.procreate` files display their thumbnails directly in File Explorer — no extra software running in the background.

### How It Works

`.procreate` files are ZIP archives containing a `QuickLook/Thumbnail.png` image. This project registers a COM **Thumbnail Provider** with the Windows Shell. When Explorer needs to display a `.procreate` file, Windows calls our provider, which streams the embedded PNG out of the ZIP and hands it back as a thumbnail bitmap. The file is never modified — read-only, stream-based extraction only.

### Highlights

- **Zero runtime overhead** — registers once into the registry, no background process
- **Survives reboots** — persistent `HKLM` registration, activate once and forget
- **Portable** — DLL path auto-detected at registration time, no hardcoded paths
- **All drives** — works on any `.procreate` file regardless of disk location
- **Read-only** — never writes, edits, or touches your artwork files
- **One-click uninstall** — `uninstall.bat` cleans up everything

### Requirements

- Windows 7 or later (64-bit)
- .NET Framework 4.x (built into Windows 10/11)
- Administrator privileges (one-time, for registration)

### Quick Start

1. Right-click `Activate.ps1` → **Run with PowerShell** (as Administrator)
2. The script compiles the DLL, registers the COM component, and restarts Explorer
3. Open any folder containing `.procreate` files — thumbnails appear immediately

To remove: run `uninstall.bat` as Administrator.

### File Overview

| File | Purpose |
|---|---|
| `ProcreateThumbnailProvider.cs` | COM thumbnail provider (C# source) |
| `Activate.ps1` | One-click compile + register + activate |
| `uninstall.bat` | Clean unregister + registry cleanup |

---

## 中文

一个轻量级的 Windows Shell 扩展，让 `.procreate` 文件在资源管理器中直接显示缩略图——无需任何后台程序常驻运行。

### 原理

`.procreate` 文件本质上是 ZIP 压缩包，内含 `QuickLook/Thumbnail.png` 缩略图。本项目向 Windows Shell 注册一个 COM **缩略图提供程序**。当资源管理器需要展示 `.procreate` 文件时，Windows 会调用该提供程序，从 ZIP 中流式提取内嵌 PNG 并以缩略图位图形式返回。整个过程**绝不写入、编辑或修改原文件**，仅做流式只读提取。

### 特色

- **零运行时开销** — 一次性写入注册表，无常驻后台进程
- **重启不失效** — 注册信息写入 `HKLM`，永久持久化，一次激活终身有效
- **随处可部署** — DLL 路径在注册时自动检测，无硬编码路径，换主机直接 git clone 即用
- **全盘生效** — 不限磁盘分区，所有 `.procreate` 文件均可显示缩略图
- **只读安全** — 绝不触碰、编辑您的画作文件
- **一键卸载** — 运行 `uninstall.bat` 即可彻底清理

### 环境要求

- Windows 7 及以上（64 位）
- .NET Framework 4.x（Windows 10/11 已内置）
- 管理员权限（仅注册时需要一次）

### 快速开始

1. 右键 `Activate.ps1` → **使用 PowerShell 运行**（以管理员身份）
2. 脚本会自动编译 DLL、注册 COM 组件并重启资源管理器
3. 打开任意包含 `.procreate` 文件的文件夹，缩略图即刻显现

卸载：以管理员身份运行 `uninstall.bat`。

### 文件说明

| 文件 | 用途 |
|---|---|
| `ProcreateThumbnailProvider.cs` | COM 缩略图提供程序（C# 源码） |
| `Activate.ps1` | 一键编译 + 注册 + 激活 |
| `uninstall.bat` | 清理注销 + 注册表清除 |

---

## 致谢 / Acknowledgments

本项目部分设计参考了 [NothingData/ProcreateViewer](https://github.com/NothingData/ProcreateViewer)，特此感谢。如果您需要在Windows上对Procreate文件作详细处理可以去看看他的项目。

Portions of this project were inspired by [NothingData/ProcreateViewer](https://github.com/NothingData/ProcreateViewer). Our sincere thanks to the original author. If you need to do detailed processing of Procreate files on Windows, you can take a look at his project.


