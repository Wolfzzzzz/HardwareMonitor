# HardwareMonitor

> [English](README_EN.md)

macOS 菜单栏硬件监控。实时看 CPU、内存、磁盘、网络、电池、亮度、进程占用，带趋势图和阈值告警，还有一个能拖来拖去的悬浮小窗。纯 SwiftUI 写的，数据全是系统接口直接读，没有第三方依赖，跑起来内存占用很低。

## 能看什么

- CPU 占用率，内存占用和组成（应用/联动/压缩/空闲），磁盘剩余
- 电池电量、健康度、循环次数、充电状态、电池温度
- 屏幕亮度
- 网络上下行速率
- 进程 CPU/内存 TOP 10，横向条形图，名称完整显示
- 温度、CPU、内存、网络的历史曲线（Swift Charts）
- 阈值告警：超了就发系统通知、提示音，菜单栏图标变红
- 主界面分成三个标签页，除了监控还有剪贴板历史、系统信息、二维码、单位换算、文本统计、编码、颜色、番茄钟、便签、常用文件夹这些工具

深浅色自适应，悬浮窗和主界面平时都隐藏，不占屏幕。

## 温度是怎么读的

温度这块单独说。Apple Silicon 上芯片温度不在 SMC 里，而是挂在 HID 传感器集线器（IOHIDEventSystemClient，usagePage 0xFF00）上。本机实测能读到 45 个传感器：PMU tdie/tdev、NAND、电池、tcal 这些，芯片温度取全部 tdie 读数的最大值。这个路径普通权限就能读，不需要 root。

这接口是私有 API，Swift 头文件里没有，所以是 dlopen + dlsym 动态调出来的。

## 风扇为什么显示 --

M 系列上风扇转速只有 SMC 的 F*Ac 这类 key 有，而新版 macOS 的 AppleSMCKeysEndpoint 对普通进程直接拒绝，所有参数组合都试过，一律 kIOReturnBadArgument。BuhoCleaner 能显示风扇，是因为它内置了一个需要开发者证书签名的 root 特权助手，普通 App 装不了这个东西。所以风扇显示 --。SMC 协议代码是完整写好的，等系统接口放开，或者换正式版系统，就能自动恢复显示。

## 构建

Xcode 直接打开 HardwareMonitor.xcodeproj，选 My Mac，⌘R 运行。或者命令行：

```bash
./build.sh
open build/Build/Products/Debug/HardwareMonitor.app
```

未签名的本地构建第一次运行要右键打开，或者去系统设置里允许。要分发的话得自己签名公证。

## 已知问题

- 风扇转速读不到，原因见上面
- 亮度走 DisplayServices 私有 API，系统大版本升级后如果符号变了会自动降级为不可用
- 只读硬件数据，不做任何写入，风扇控制、亮度调节这些都没做

## 环境

macOS 14+ 都能跑。开发机是 macOS 27 beta + Apple M5。Intel 机器理论上也支持，SMC 那条备用路径在 Intel 上可以直接读温度和风扇。
