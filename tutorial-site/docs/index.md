# HardwareMonitor 运行教程（Xcode）

本教程面向首次使用 Xcode 的用户，按步骤操作即可完成编译与运行。

## 一、环境要求

- 操作系统：macOS 14 或更高版本
- 开发工具：Xcode 16 或更高版本（通过 App Store 免费获取）

验证方法：在终端执行 `xcodebuild -version`，输出中应包含 Xcode 版本号。

## 二、获取源代码

**方式一（命令行）**：

```bash
git clone https://github.com/Wolfzzzzz/HardwareMonitor.git
```

**方式二（浏览器下载）**：

1. 访问 https://github.com/Wolfzzzzz/HardwareMonitor
2. 点击页面右上角绿色 **Code** 按钮
3. 选择 **Download ZIP** 并解压

## 三、打开工程

进入 `HardwareMonitor` 目录，双击 **`HardwareMonitor.xcodeproj`** 文件。
请注意：目录中存在同名的普通文件夹，应选择带有 `.xcodeproj` 后缀的工程文件。

## 四、编译并运行

Xcode 窗口顶部工具栏设置如下：

1. Scheme 选择框：选择 **HardwareMonitor**
2. 运行目标选择框：选择 **My Mac**
3. 点击工具栏 **运行** 按钮（▶），或按快捷键 **⌘R**

首次编译耗时较长，请等待编译完成。

## 五、首次运行

1. 系统弹出通知权限请求时，点击 **允许**（温度告警功能依赖通知权限）。
2. 如出现「无法验证开发者」提示，请右键点击应用图标，选择 **打开**，再确认一次即可运行。

## 六、功能入口

- 菜单栏右上角（时间显示区域）出现温度计图标，点击后显示概览面板（CPU、内存、磁盘、温度、电池、亮度、网络）。
- 选择「打开主界面」可查看完整窗口（趋势图、温度传感器列表、剪贴板历史、工具集）。
- 选择「显示悬浮窗」可显示置顶小窗，支持拖动。

## 七、常见问题

| 问题 | 解决方案 |
|---|---|
| 工程无法打开 | Xcode 版本低于 16，请升级 |
| 编译失败（Build Failed） | 确认 Scheme 为 HardwareMonitor、运行目标为 My Mac |
| 菜单栏无图标 | 等待 1-2 秒初始化，或检查通知权限 |
| 面板数据为空 | 等待下一次采样完成（约 2 秒）后重新打开 |
| 风扇转速显示 "--" | 新版 macOS 限制普通进程读取风扇数据，属正常现象；温度监控不受影响 |
| 退出应用 | 点击菜单栏图标，选择「退出」 |

## 八、后续启动

- 退出后重新启动：进入 `build/Build/Products/Debug/` 目录，双击 `HardwareMonitor.app`。
- 或在 Xcode 中重新执行 ⌘R。

---

如有其他问题，可在测试问卷中反馈：https://wj.qq.com/s2/27539678/o70y
