# NovaLaunch

一款 macOS 启动器，采用 iOS 27 风格的液态玻璃（Liquid Glass）界面，主打流畅原生的拖拽体验与智能应用分组。

🌐 **在线演示 / Live Demo**：[https://novalaunch.pages.dev/](https://novalaunch.pages.dev/)

## 功能特性

- **液态玻璃 UI**：iOS 27 动态玻璃质感，分层玻璃背景、呼吸动画、药丸形控件与景深阴影。
- **拖拽排序 / 建组**：在「全部应用」中拖拽图标即可插入排序；拖到目标上停顿可收纳进文件夹。
- **智能分组**：自定义应用分组、文件夹命名与重排。
- **全局唤起**：通过快捷键随时唤起启动器。

## 系统要求

- macOS 14 及以上
- Xcode 15+（从源码构建）

## 从源码构建

```bash
git clone https://github.com/anson55sky/NovaLaunch.git
cd NovaLaunch
open NovaLaunch.xcodeproj
# 在 Xcode 中选择你的开发者签名，Build & Run（Release）
```

> 注意：本仓库为源码仓库，未包含编译产物（`.app` / `DerivedData` 等），请使用 Xcode 自行构建。

## 目录结构

```
NovaLaunch/          主工程 Swift 源码
NovaLaunch.xcodeproj Xcode 工程
modules/NovaLaunchKit 核心工具模块
docs/                设计文档
scripts/release.sh   发布脚本
```

## 开源协议

基于 [Apache License 2.0](LICENSE) 开源。
