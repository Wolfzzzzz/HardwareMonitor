# HardwareMonitor 新手运行教程（Xcode 版）

第一次用 Xcode 也没关系，照着做，10 分钟跑起来。

## 一、准备

- 一台 Mac，系统 **macOS 14 或更高**
- 安装 **Xcode**（App Store 搜 Xcode，免费，版本 16 以上）

> 确认方法：App Store 已购项目里能找到；或者终端输入 `xcodebuild -version` 能看到版本号。

## 二、下载代码

**方式 A（推荐，终端）**：
```bash
git clone https://github.com/Wolfzzzzz/HardwareMonitor.git
```

**方式 B（网页下载）**：
1. 浏览器打开 https://github.com/Wolfzzzzz/HardwareMonitor
2. 点绿色 **Code** 按钮 → **Download ZIP**
3. 下载完双击解压

## 三、打开工程

进到 `HardwareMonitor` 文件夹，**双击 `HardwareMonitor.xcodeproj`**。

注意：文件夹里有两个长得很像的东西，要双击的是带 **`.xcodeproj`** 后缀的那个，别点错成里面的 `HardwareMonitor` 文件夹。

## 四、运行

Xcode 打开后，看窗口**最上面一排**：

1. **左边**的 Scheme 下拉框：选 **HardwareMonitor**
2. **旁边**的设备下拉框：选 **My Mac**
3. 按键盘 **⌘R**（或者点左上角的 **▶ 播放按钮**）

开始编译，第一次会慢一点（几十秒），等它就完事了。

## 五、首次运行会弹窗

1. **通知权限**：点 **允许**（温度告警要用）
2. 如果弹出「无法验证开发者」之类的提示：**右键**点 App 图标 → **打开** → 再点一次**打开**就进去了

## 六、看效果

- 屏幕**最右上角**（时间那一排）会出现一个 🌡️ **温度计图标**
- 点它 → 弹出概览面板：CPU、内存、磁盘、温度、电池、亮度、网络
- 点「**打开主界面**」→ 完整大窗口（趋势图、温度传感器列表、剪贴板历史、各种工具）
- 点「**显示悬浮窗**」→ 置顶小窗，按住能拖动

## 常见问题

| 问题 | 解决办法 |
|---|---|
| 双击工程没反应 / 打不开 | Xcode 版本太旧（要 16+），升级 Xcode |
| 点 ▶ 报错 Build failed | 检查 Scheme 是 HardwareMonitor、设备是 My Mac |
| 运行了菜单栏没图标 | 看右上角最边上；刚启动要等 1~2 秒 |
| 面板里数据全是空的 | 等 2 秒让它采一次样，再点菜单栏图标 |
| 风扇显示 -- | 正常，新版 macOS 不给普通 App 读风扇权限，温度不受影响 |
| 想关掉 App | 点菜单栏图标 → 退出 |

## 想关掉 / 重开

- 退出：菜单栏图标 → **退出**
- 下次启动：访达进到 `build/Build/Products/Debug/` 双击 `HardwareMonitor.app`（编译产物），或重新在 Xcode 里 ⌘R

---

遇到问题截个图，随时找作者（在填测试问卷就行：https://wj.qq.com/s2/27539678/o70y）。
