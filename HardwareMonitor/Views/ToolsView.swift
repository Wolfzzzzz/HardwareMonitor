import SwiftUI
import CoreImage
import CryptoKit
import Darwin

// MARK: - 工具页主容器（左侧工具列表 + 右侧内容）

struct ToolsView: View {
    @EnvironmentObject private var model: AppModel

    private let tools: [(icon: String, name: String)] = [
        ("bolt.fill", "快捷操作"),
        ("info.circle", "系统信息"),
        ("qrcode", "二维码"),
        ("arrow.left.arrow.right", "单位换算"),
        ("textformat", "文本统计"),
        ("curlybraces", "编码工具"),
        ("paintpalette", "颜色工具"),
        ("timer", "番茄钟"),
        ("note.text", "便签"),
        ("folder", "常用文件夹")
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                contentView
                    .padding(16)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(tools.indices, id: \.self) { i in
                Button {
                    model.toolTab = i
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tools[i].icon)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text(tools[i].name)
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(model.toolTab == i ? Color.accentColor.opacity(0.2) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(8)
        .frame(width: 148)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var contentView: some View {
        switch model.toolTab {
        case 0: QuickToolsView()
        case 1: SystemInfoView()
        case 2: QRCodeView()
        case 3: UnitConvertView()
        case 4: TextStatView()
        case 5: EncodeToolsView()
        case 6: ColorToolsView()
        case 7: PomodoroView()
        case 8: NoteView()
        default: FolderView()
        }
    }
}

// MARK: - 通用小组件

private struct ToolSectionTitle: View {
    let title: String
    let icon: String
    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .padding(.bottom, 4)
    }
}

/// 系统信息采集
enum SysInfo {
    static var hostName: String { Host.current().localizedName ?? "unknown" }
    static var userName: String { NSUserName() }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var model: String { sysctlString("hw.model") }
    static var chip: String { sysctlString("machdep.cpu.brand_string") }

    static var memory: String {
        String(format: "%.1f GB", Double(ProcessInfo.processInfo.physicalMemory) / 1e9)
    }

    static var localIP: String { interfaceInfo(ipv4: true) }
    static var macAddress: String { interfaceInfo(ipv4: false) }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }

    /// 枚举 en* 接口；ipv4=true 返回首个 IPv4 地址，否则返回 MAC 地址
    private static func interfaceInfo(ipv4: Bool) -> String {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return "unknown" }
        defer { freeifaddrs(ifaddrPtr) }
        var ptr = ifaddrPtr
        while let p = ptr {
            let name = String(cString: p.pointee.ifa_name)
            if name.hasPrefix("en"), let addr = p.pointee.ifa_addr {
                if ipv4 {
                    if addr.pointee.sa_family == UInt8(AF_INET) {
                        var host = [CChar](repeating: 0, count: 128)
                        getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                        let ip = String(cString: host)
                        if !ip.hasPrefix("169.254"), ip != "127.0.0.1" { return ip }
                    }
                } else if addr.pointee.sa_family == UInt8(AF_LINK), let data = p.pointee.ifa_data {
                    let dl = data.assumingMemoryBound(to: sockaddr_dl.self).pointee
                    let len = Int(dl.sdl_alen)
                    if len == 6 {
                        let base = data.advanced(by: Int(dl.sdl_nlen)).assumingMemoryBound(to: UInt8.self)
                        let mac = (0..<len).map { String(format: "%02X", base[$0]) }.joined(separator: ":")
                        if mac != "00:00:00:00:00:00" { return mac }
                    }
                }
            }
            ptr = p.pointee.ifa_next
        }
        return ipv4 ? "未连接" : "unknown"
    }
}

// MARK: - 0 快捷操作

struct QuickToolsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSectionTitle(title: "快捷操作", icon: "bolt.fill")
            HStack(spacing: 12) {
                toolButton("锁屏", icon: "lock.fill", tint: .blue) { model.lockScreen() }
                toolButton("显示器休眠", icon: "moon.fill", tint: .indigo) { model.sleepDisplay() }
                toolButton("清空剪贴板", icon: "trash", tint: .red) { model.clearSystemClipboard() }
            }
            Text("锁屏：模拟系统锁屏快捷键 ⌃⌘Q。首次使用需在「系统设置 → 隐私与安全性 → 辅助功能」中允许本 App。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(.caption)
            }
            .frame(width: 100, height: 60)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.15)))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 1 系统信息

struct SystemInfoView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSectionTitle(title: "系统信息（点击复制）", icon: "info.circle")
            ForEach(infoRows, id: \.0) { row in
                infoRow(row.0, value: row.1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoRows: [(String, String)] {
        [
            ("主机名", SysInfo.hostName),
            ("用户名", SysInfo.userName),
            ("内网 IP", SysInfo.localIP),
            ("MAC 地址", SysInfo.macAddress),
            ("macOS", SysInfo.osVersion),
            ("机型", SysInfo.model),
            ("芯片", SysInfo.chip),
            ("内存", SysInfo.memory),
            ("核心数", "\(ProcessInfo.processInfo.activeProcessorCount) 核")
        ]
    }

    private func infoRow(_ key: String, value: String) -> some View {
        let isCopied = model.copiedInfoKey == key
        return HStack(spacing: 8) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                model.copiedInfoKey = key
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { model.copiedInfoKey = nil }
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(isCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
}

// MARK: - 2 二维码

struct QRCodeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSectionTitle(title: "二维码生成", icon: "qrcode")
            TextField("输入文本或链接", text: $model.qrText)
                .textFieldStyle(.roundedBorder)
            if let img = qrImage(from: model.qrText), !model.qrText.isEmpty {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 190, height: 190)
                    .padding(.top, 8)
            } else {
                Text("内容过长或为空，无法生成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func qrImage(from text: String) -> NSImage? {
        guard let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

// MARK: - 3 单位换算

struct UnitConvertView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSectionTitle(title: "单位换算", icon: "arrow.left.arrow.right")
            Picker("类别", selection: $model.convertCategory) {
                ForEach(UnitConv.categories.indices, id: \.self) { i in
                    Text(UnitConv.categories[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                TextField("数值", text: $model.convertValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Picker("", selection: $model.convertFrom) {
                    ForEach(UnitConv.units[model.convertCategory].indices, id: \.self) { i in
                        Text(UnitConv.units[model.convertCategory][i]).tag(i)
                    }
                }
                .pickerStyle(.menu)
                Text("→")
                Picker("", selection: $model.convertTo) {
                    ForEach(UnitConv.units[model.convertCategory].indices, id: \.self) { i in
                        Text(UnitConv.units[model.convertCategory][i]).tag(i)
                    }
                }
                .pickerStyle(.menu)
            }

            let result = converted
            LabeledContent("结果") {
                Text(result)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var converted: String {
        guard let v = Double(model.convertValue) else { return "输入无效" }
        let r = UnitConv.convert(cat: model.convertCategory, value: v, from: model.convertFrom, to: model.convertTo)
        guard let r else { return "--" }
        return String(format: "%.6g", r) + " " + UnitConv.units[model.convertCategory][model.convertTo]
    }
}

enum UnitConv {
    static let categories = ["长度", "重量", "温度", "数据大小", "速度"]
    static let units: [[String]] = [
        ["米 m", "千米 km", "厘米 cm", "毫米 mm", "英里 mi", "码 yd", "英尺 ft", "英寸 in"],
        ["千克 kg", "克 g", "毫克 mg", "磅 lb", "盎司 oz", "吨 t"],
        ["摄氏度 °C", "华氏度 °F", "开尔文 K"],
        ["字节 B", "KB", "MB", "GB", "TB"],
        ["米/秒 m/s", "千米/时 km/h", "英里/时 mph", "节 knot"]
    ]

    private static func toBase(_ cat: Int, _ unit: Int) -> Double {
        switch cat {
        case 0: return [1, 1000, 0.01, 0.001, 1609.344, 0.9144, 0.3048, 0.0254][unit]
        case 1: return [1, 0.001, 1e-6, 0.45359237, 0.0283495231, 1000][unit]
        case 3: return [1, 1024, 1048576, 1073741824, 1099511627776][unit]
        default: return [1, 1000.0 / 3600.0, 1609.344 / 3600.0, 1852.0 / 3600.0][unit]
        }
    }

    static func convert(cat: Int, value: Double, from: Int, to: Int) -> Double? {
        if cat == 2 {
            let c: Double
            switch from {
            case 0: c = value
            case 1: c = (value - 32) * 5 / 9
            default: c = value - 273.15
            }
            switch to {
            case 0: return c
            case 1: return c * 9 / 5 + 32
            default: return c + 273.15
            }
        }
        return value * toBase(cat, from) / toBase(cat, to)
    }
}

// MARK: - 4 文本统计

struct TextStatView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSectionTitle(title: "文本统计", icon: "textformat")
            TextEditor(text: $model.statText)
                .font(.body)
                .frame(minHeight: 140)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                statCell("字符数", "\(model.statText.count)")
                statCell("非空格字符", "\(model.statText.filter { !$0.isWhitespace }.count)")
                statCell("行数", "\(model.statText.split(separator: "\n").count)")
                statCell("词数(英文)", "\(model.statText.split(whereSeparator: { $0.isWhitespace }).count)")
                statCell("预计朗读", readTime)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readTime: String {
        let chars = Double(model.statText.filter { !$0.isWhitespace }.count)
        let minutes = chars / 300
        return minutes < 0.5 ? LZ.t("不足 1 分钟", "under a minute") : String(format: LZ.t("约 %.0f 分钟", "about %.0f min"), minutes)
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - 5 编码工具

struct EncodeToolsView: View {
    @EnvironmentObject private var model: AppModel
    private let modes = ["URL 编码", "URL 解码", "Base64 编码", "Base64 解码", "MD5", "SHA256"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSectionTitle(title: "编码 / 哈希工具", icon: "curlybraces")
            Picker("模式", selection: $model.encodeMode) {
                ForEach(modes.indices, id: \.self) { i in Text(modes[i]).tag(i) }
            }
            .pickerStyle(.segmented)

            TextField("输入", text: $model.encodeInput)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.encodeInput) { _, _ in model.encodeOutput = compute() }
                .onChange(of: model.encodeMode) { _, _ in model.encodeOutput = compute() }

            HStack {
                Text(model.encodeOutput)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.encodeOutput, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { model.encodeOutput = compute() }
    }

    private func compute() -> String {
        let input = model.encodeInput
        switch model.encodeMode {
        case 0: return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        case 1: return input.removingPercentEncoding ?? ""
        case 2: return Data(input.utf8).base64EncodedString()
        case 3: return String(data: Data(base64Encoded: input) ?? Data(), encoding: .utf8) ?? "解码失败"
        case 4: return Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        default: return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }
}

// MARK: - 6 颜色工具

struct ColorToolsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSectionTitle(title: "颜色工具（HEX → RGB）", icon: "paintpalette")
            TextField("#RRGGBB", text: $model.colorHex)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            if let rgb = rgbFromHex(model.colorHex) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(rgb.color)
                    .frame(height: 60)
                    .overlay(
                        Text("预览")
                            .font(.caption)
                            .foregroundStyle(rgb.isLight ? .black : .white)
                    )
                LabeledContent("RGB") { Text("\(rgb.r), \(rgb.g), \(rgb.b)").font(.caption.monospacedDigit()) }
                HStack(spacing: 8) {
                    copyChip("HEX", model.colorHex.uppercased())
                    copyChip("RGB 文本", "\(rgb.r), \(rgb.g), \(rgb.b)")
                }
            } else {
                Text("格式无效，请输入 #RRGGBB")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyChip(_ label: String, _ value: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Text("复制 \(label)")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.blue.opacity(0.15)))
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }

    private func rgbFromHex(_ hex: String) -> (r: Int, g: Int, b: Int, color: Color, isLight: Bool)? {
        var h = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        let r = Int((v >> 16) & 0xff), g = Int((v >> 8) & 0xff), b = Int(v & 0xff)
        return (r, g, b,
                Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255),
                Double(r) * 0.299 + Double(g) * 0.587 + Double(b) * 0.114 > 150)
    }
}

// MARK: - 7 番茄钟

struct PomodoroView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSectionTitle(title: "番茄钟", icon: "timer")
            HStack(alignment: .center, spacing: 18) {
                CircleDial(minutes: model.pomoMinutes) { m in
                    model.setPomodoroMinutes(m)
                }
                .disabled(model.pomoRunning)
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 10) {
                    Text("滑动圆盘调整时长")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach([15, 25, 45, 60], id: \.self) { m in
                            Button("\(m) 分") { model.setPomodoroMinutes(m) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(model.pomoRunning)
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("", value: Binding(
                            get: { Double(model.pomoMinutes) },
                            set: { model.setPomodoroMinutes(Int($0)) }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 76)
                        .disabled(model.pomoRunning)
                        Text("或输入分钟")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(String(format: "%02d:%02d", model.pomoRemaining / 60, model.pomoRemaining % 60))
                .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(model.pomoRunning ? .blue : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            ProgressView(value: progress)
                .tint(.blue)

            HStack(spacing: 10) {
                Button(model.pomoRunning ? "暂停" : "开始") {
                    model.pomoRunning ? model.stopPomodoro() : model.startPomodoro()
                }
                .buttonStyle(.borderedProminent)
                Button("重置") { model.resetPomodoro() }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .frame(maxWidth: .infinity)

            Text("结束后会发送系统通知。专注模式，加油！")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progress: Double {
        let total = Double(model.pomoMinutes * 60)
        guard total > 0 else { return 0 }
        return 1.0 - Double(model.pomoRemaining) / total
    }
}

/// 番茄钟圆盘：按住并沿圆周滑动调整分钟（1~120），一圈 = 120 分钟
struct CircleDial: View {
    let minutes: Int
    let onChange: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 2 - 22
            let angle = (Double(minutes) - 1) / 120 * 2 * .pi - .pi / 2
            let handle = CGPoint(x: center.x + radius * cos(angle),
                                 y: center.y + radius * sin(angle))

            ZStack {
                // 底环
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 10)
                // 进度弧
                Circle()
                    .trim(from: 0, to: Double(minutes) / 120)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                // 刻度标签
                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { m in
                    let a = (Double(m) - 1) / 120 * 2 * .pi - .pi / 2
                    Text("\(m)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .position(x: center.x + (radius - 16) * cos(a),
                                  y: center.y + (radius - 16) * sin(a))
                }
                // 中心数值
                VStack(spacing: 0) {
                    Text("\(minutes)")
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("分钟")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .position(center)
                // 手柄
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)
                    .shadow(color: .blue.opacity(0.4), radius: 4)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 2)
                    )
                    .position(handle)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = CGVector(dx: g.location.x - center.x,
                                         dy: g.location.y - center.y)
                        let dist = sqrt(v.dx * v.dx + v.dy * v.dy)
                        guard dist > 18 else { return }  // 中心附近忽略，防抖动
                        var a = atan2(v.dy, v.dx) + .pi / 2
                        if a < 0 { a += 2 * .pi }
                        let m = Int(a / (2 * .pi) * 120) + 1
                        onChange(max(1, min(120, m)))
                    }
            )
        }
        .accessibilityLabel("时长圆盘")
    }
}

// MARK: - 8 便签

struct NoteView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSectionTitle(title: "便签（自动保存）", icon: "note.text")
            TextEditor(text: $model.noteText)
                .font(.body)
                .frame(minHeight: 240)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
            HStack {
                Text("\(model.noteText.count) 字符 · 保存在本机")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空") { model.noteText = "" }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 9 常用文件夹

struct FolderView: View {
    private let folders: [(name: String, icon: String, path: String)] = [
        ("桌面", "desktopcomputer", "\(NSHomeDirectory())/Desktop"),
        ("下载", "arrow.down.circle", "\(NSHomeDirectory())/Downloads"),
        ("文稿", "doc.text", "\(NSHomeDirectory())/Documents"),
        ("图片", "photo", "\(NSHomeDirectory())/Pictures"),
        ("音乐", "music.note", "\(NSHomeDirectory())/Music"),
        ("影片", "film", "\(NSHomeDirectory())/Movies"),
        ("应用程序", "app.badge", "/Applications")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSectionTitle(title: "常用文件夹（点击打开）", icon: "folder")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(folders, id: \.name) { f in
                    if FileManager.default.fileExists(atPath: f.path) {
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: f.path))
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: f.icon).font(.system(size: 20))
                                Text(f.name).font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
