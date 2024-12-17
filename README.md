# iOS IPA 重签名工具

一个使用 SwiftUI 开发的 macOS 应用程序，用于对 iOS IPA 文件进行重签名。

## 功能特性

- 支持选择 IPA 文件进行重签名
- 支持选择描述文件（.mobileprovision）
- 从系统钥匙串中选择签名证书
- 可选择性修改 Bundle ID
- 自定义输出路径
- 实时显示重签名进度
- 支持对应用内的框架和动态库进行签名

## 系统要求

- macOS 11.0 或更高版本
- Xcode 命令行工具

## 使用方法

1. 选择需要重签名的 IPA 文件
2. 选择对应的描述文件（.mobileprovision）
3. 从下拉列表中选择签名证书
4. （可选）输入新的 Bundle ID
5. 选择输出路径
6. 点击"开始重签名"按钮

## 注意事项

- 确保系统已安装 Xcode 命令行工具
- 确保钥匙串中有可用的签名证书
- 描述文件必须与选择的证书匹配
- 建议在修改 Bundle ID 时确保与描述文件中的 Bundle ID 匹配

## 开发环境

- macOS Sonoma 14.0 或更高版本
- Xcode 15.0 或更高版本
- Swift 5.9 或更高版本

## 项目结构

- `ContentView.swift`: 主界面 UI 实现
- `ResignService.swift`: 重签名核心逻辑实现
- `IPAResignerApp.swift`: 应用程序入口
- `IPAResigner.entitlements`: 应用程序权限配置

## 许可证

MIT License

