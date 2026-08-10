import Foundation
import Network

/// 局域网远程监控：基于 NWListener 的迷你 HTTP 服务
/// GET /            → 深色响应式监控页面（手机/电脑浏览器均可访问）
/// GET /api/status  → 当前快照 JSON
final class RemoteMonitorServer {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "cn.zzn.hwmon.remote", qos: .utility)

    /// 快照数据源（由 AppModel 注入）
    var onSnapshot: (() -> SystemSnapshot?)?
    /// 远程动作回调（lock/sleep，由 AppModel 注入）
    var onAction: ((String) -> Void)?

    var isRunning: Bool { listener != nil }
    var port: UInt16 = 8900

    func start() throws {
        stop()
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            self.connections.append(conn)
            conn.start(queue: self.queue)
            self.receive(on: conn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            if let data, !data.isEmpty {
                let req = String(data: data, encoding: .utf8) ?? ""
                let (code, contentType, body) = self.route(req)
                let header = "HTTP/1.1 \(code)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
                conn.send(content: Data((header + body).utf8), completion: .contentProcessed { _ in
                    conn.cancel()
                    self.connections.removeAll { $0 === conn }
                })
                return
            }
            if isComplete {
                self.connections.removeAll { $0 === conn }
                return
            }
            self.receive(on: conn)
        }
    }

    private func route(_ request: String) -> (String, String, String) {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        let method = parts.first ?? "GET"
        let path = parts.dropFirst().first ?? "/"
        if path.hasPrefix("/api/status") {
            return ("200 OK", "application/json; charset=utf-8", statusJSON())
        }
        if method == "POST", path.hasPrefix("/api/action") {
            // body 形如 action=lock
            let body = request.components(separatedBy: "\r\n\r\n").dropFirst().first ?? ""
            let kv = body.components(separatedBy: "=")
            if kv.count >= 2 { onAction?(kv[1]) }
            return ("200 OK", "application/json; charset=utf-8", "{\"ok\":true}")
        }
        return ("200 OK", "text/html; charset=utf-8", Self.pageHTML)
    }

    private func statusJSON() -> String {
        guard let s = onSnapshot?() else { return "{\"ok\":false}" }
        struct P: Encodable { let name: String; let cpu: Double; let memMB: Double }
        let procs = s.topProcesses.prefix(5).map { P(name: $0.name, cpu: $0.cpuPercent, memMB: $0.memoryMB) }
        struct Out: Encodable {
            let ok: Bool
            let cpu: Double
            let memPercent: Double
            let memUsed: Double
            let memTotal: Double
            let cpuTemp: Double?
            let gpuTemp: Double?
            let battery: Int?
            let charging: Bool
            let netDown: Double
            let netUp: Double
            let diskPercent: Double
            let procs: [P]
        }
        let o = Out(
            ok: true,
            cpu: s.cpuPercentValue,
            memPercent: s.memPercentValue * 100,
            memUsed: Double(s.memUsed) / 1024 / 1024 / 1024,
            memTotal: Double(s.memTotal) / 1024 / 1024 / 1024,
            cpuTemp: s.cpuTempC, gpuTemp: s.gpuTempC,
            battery: s.batteryPercent, charging: s.batteryCharging,
            netDown: s.netDown / 1024 / 1024, netUp: s.netUp / 1024 / 1024,
            diskPercent: s.diskPercentValue * 100,
            procs: procs
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? enc.encode(o) else { return "{\"ok\":false}" }
        return String(data: data, encoding: .utf8) ?? "{\"ok\":false}"
    }

    /// 内嵌监控页面（深色、响应式、轮询 /api/status）
    private static let pageHTML = """
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HardwareMonitor · 远程监控</title>
    <style>
      :root{--bg:#0d1117;--card:#161b22;--border:#2d333b;--text:#e6edf3;--sub:#8b949e;--accent:#58a6ff}
      *{margin:0;padding:0;box-sizing:border-box}
      body{font-family:-apple-system,"PingFang SC",sans-serif;background:var(--bg);color:var(--text);padding:20px;line-height:1.6}
      h1{font-size:20px;margin-bottom:4px}
      .sub{color:var(--sub);font-size:13px;margin-bottom:16px}
      .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px}
      .card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:14px}
      .card .label{color:var(--sub);font-size:12px}
      .card .value{font-size:26px;font-weight:700;margin-top:2px}
      .card .value small{font-size:13px;color:var(--sub);font-weight:400}
      .bar{height:6px;background:#21262d;border-radius:3px;margin-top:8px;overflow:hidden}
      .bar>div{height:100%;background:var(--accent);border-radius:3px;transition:width .4s}
      .procs{margin-top:16px}
      .procs h2{font-size:14px;color:var(--sub);margin-bottom:8px;font-weight:600}
      .proc{display:flex;align-items:center;gap:8px;padding:6px 0;border-bottom:1px solid var(--border);font-size:13px}
      .proc .name{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      .proc .cpu{width:52px;text-align:right;color:var(--sub)}
      .ok{color:#3fb950;margin-left:6px}
      @media(max-width:400px){.card .value{font-size:22px}}
    </style>
    </head>
    <body>
      <h1>HardwareMonitor <span class="ok">●</span></h1>
      <div class="sub" id="time">实时监控 · 等待数据…</div>
      <div class="grid">
        <div class="card"><div class="label">CPU 占用</div><div class="value" id="cpu">--<small>%</small></div><div class="bar"><div id="cpuBar" style="width:0%"></div></div></div>
        <div class="card"><div class="label">内存</div><div class="value" id="mem">--<small>%</small></div><div class="bar"><div id="memBar" style="width:0%"></div></div></div>
        <div class="card"><div class="label">芯片温度</div><div class="value" id="temp">--<small>°C</small></div></div>
        <div class="card"><div class="label">电池</div><div class="value" id="batt">--<small>%</small></div></div>
        <div class="card"><div class="label">下行</div><div class="value" id="down">--<small>MB/s</small></div></div>
        <div class="card"><div class="label">上行</div><div class="value" id="up">--<small>MB/s</small></div></div>
        <div class="card"><div class="label">磁盘已用</div><div class="value" id="disk">--<small>%</small></div></div>
      </div>
      <div class="procs"><h2>进程 TOP 5</h2><div id="procs"></div></div>
      <div class="controls" style="margin-top:16px;display:flex;gap:10px">
        <button onclick="act('lock')" style="flex:1;padding:10px;border-radius:8px;border:1px solid var(--border);background:var(--card);color:var(--text);cursor:pointer">🔒 远程锁屏</button>
        <button onclick="act('sleep')" style="flex:1;padding:10px;border-radius:8px;border:1px solid var(--border);background:var(--card);color:var(--text);cursor:pointer">💤 显示器休眠</button>
      </div>
      <script>
        function fmt(n){ return (n==null||isNaN(n)) ? "--" : n.toFixed(0); }
        function tick(){
          fetch('/api/status').then(r=>r.json()).then(d=>{
            if(!d.ok) return;
            document.getElementById('cpu').innerHTML = fmt(d.cpu)+'<small>%</small>';
            document.getElementById('cpuBar').style.width = Math.min(100,d.cpu)+'%';
            document.getElementById('mem').innerHTML = fmt(d.memPercent)+'<small>%</small>';
            document.getElementById('memBar').style.width = Math.min(100,d.memPercent)+'%';
            document.getElementById('temp').innerHTML = fmt(d.cpuTemp)+'<small>°C</small>';
            document.getElementById('batt').innerHTML = (d.battery==null?'--':fmt(d.battery))+'<small>%</small>';
            document.getElementById('down').innerHTML = (d.netDown||0).toFixed(1)+'<small>MB/s</small>';
            document.getElementById('up').innerHTML = (d.netUp||0).toFixed(1)+'<small>MB/s</small>';
            document.getElementById('disk').innerHTML = fmt(d.diskPercent)+'<small>%</small>';
            var p=''; (d.procs||[]).forEach(function(x){ p+='<div class="proc"><span class="name">'+x.name+'</span><span class="cpu">'+fmt(x.cpu)+'%</span></div>'; });
            document.getElementById('procs').innerHTML = p || '<div class="sub">无数据</div>';
            document.getElementById('time').textContent = '实时监控 · 更新于 ' + new Date().toLocaleTimeString();
          }).catch(function(){ document.getElementById('time').textContent = '连接中断，正在重试…'; });
        }
        tick(); setInterval(tick, 2000);
        function act(a){
          fetch('/api/action',{method:'POST',body:'action='+a})
            .then(function(){ document.getElementById('time').textContent = '已发送「'+(a==='lock'?'锁屏':'休眠')+'」指令'; });
        }
      </script>
    </body>
    </html>
    """
}
