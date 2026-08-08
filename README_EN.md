# HardwareMonitor

A macOS menu bar hardware monitor. Live CPU, memory, disk, network, battery, brightness and process stats, with trend charts and threshold alerts, plus a small draggable floating panel. Built with SwiftUI, all data comes straight from system APIs. No third-party dependencies.

## What it shows

- CPU usage, memory usage and breakdown, free disk space
- Battery level, health, cycle count, charging state and temperature
- Screen brightness
- Network upload / download rate
- Top 10 processes by CPU and memory, as horizontal bars
- Live trend curves for temperature, CPU, memory and network (Swift Charts)
- Threshold alerts: system notification + sound when exceeded, menu bar icon turns red
- Clipboard history, system info, QR code, unit converter, text stats, encoding tools, color picker, pomodoro timer, sticky notes, quick folders
- Dark / light mode support

A note on temperature. On Apple Silicon the chip temperature lives in the HID sensor hub (IOHIDEventSystemClient), not in SMC. On this machine it reads 45 sensors: PMU tdie/tdev, NAND, battery, tcal and so on. Chip temperature is the max tdie value. This path works with normal user permissions, no root needed.

Fan speed is a different story. On M-series Macs fan RPM only exists in SMC keys like F*Ac, and recent macOS refuses to expose that interface to regular processes (every parameter combination we tried returns kIOReturnBadArgument). BuhoCleaner can show fan speed because it ships a root privileged helper that needs a signed developer certificate, which a normal app can't install. So fan speed shows "--", but the full SMC protocol is implemented and will kick in automatically if the system opens the interface up.

## Build

Open HardwareMonitor.xcodeproj in Xcode and press Cmd+R. Or from the command line:

```bash
./build.sh
open build/Build/Products/Debug/HardwareMonitor.app
```

Unsigned local builds need a right-click → Open on first launch, or allow it in System Settings. Sign and notarize the app if you want to distribute it.

## Known limitations

- Fan RPM is not readable, see above
- Brightness uses the DisplayServices private API; if the symbol changes in a future macOS it degrades to "unavailable" automatically
- Read-only: this app never writes to or adjusts hardware (no fan control, no brightness control)

## Environment

Requires macOS 14+. Developed on macOS 27 beta with an Apple M5; Intel Macs should work too (the SMC fallback path reads temperature and fan directly on Intel).
