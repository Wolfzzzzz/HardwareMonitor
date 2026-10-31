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

    /// 内嵌监控页面（Grafana 风格深色面板：stat + sparkline + 时序图 + 阈值变色，轮询 /api/status）
    private static let pageHTML = """
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HardwareMonitor · 远程监控</title>
    <style>
      :root{--bg:#111217;--panel:#181b1f;--border:#24272b;--text:#ccccdc;--sub:#8e8ea0;--green:#73bf69;--yellow:#fade2a;--red:#f2495c;--blue:#5794f2;--orange:#ff9830;--purple:#b877d9}
      *{margin:0;padding:0;box-sizing:border-box}
      body{font-family:-apple-system,"PingFang SC",sans-serif;background:var(--bg);color:var(--text);line-height:1.5;padding:16px}
      .wrap{max-width:1100px;margin:0 auto}
      header{display:flex;justify-content:space-between;align-items:center;margin-bottom:4px}
      .brand{display:flex;align-items:center;gap:10px}
      h1{font-size:16px;font-weight:600}
      .dot{width:9px;height:9px;border-radius:50%;display:inline-block;background:#5a5c61}
      .dot.ok{background:var(--green);box-shadow:0 0 6px var(--green)}
      .dot.err{background:var(--red)}
      .tag{font-size:10px;color:var(--sub);border:1px solid var(--border);padding:2px 6px;border-radius:3px;letter-spacing:1px}
      .hbtns{display:flex;gap:8px}
      button{padding:6px 14px;border-radius:4px;border:1px solid #33363c;background:#22252b;color:var(--text);font-size:12px;cursor:pointer}
      button:hover{background:#3a3d44}
      #time{color:var(--sub);font-size:12px;margin-bottom:14px}
      .row1{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:8px}
      .row2{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:8px}
      .panel{background:var(--panel);border:1px solid var(--border);border-radius:4px;padding:10px 12px}
      .ptitle{font-size:11px;color:var(--sub);letter-spacing:.4px;display:flex;justify-content:space-between;align-items:center}
      .legend{font-size:10px;font-weight:400}
      .legend i{display:inline-block;width:8px;height:8px;border-radius:2px;margin:0 4px 0 10px;vertical-align:middle}
      .stat .value{font-size:28px;font-weight:500;margin:4px 0 2px}
      .stat .value small{font-size:13px;color:var(--sub);font-weight:400;margin-left:2px}
      .stat .subv{font-size:11px;color:var(--sub);min-height:14px}
      canvas.spark{display:block;width:100%;height:34px;margin-top:6px}
      canvas.chart{display:block;width:100%;height:180px;margin-top:8px}
      table{width:100%;border-collapse:collapse;margin-top:6px}
      th{text-align:left;color:var(--sub);font-weight:500;font-size:11px;border-bottom:1px solid var(--border);padding:6px 8px}
      td{padding:6px 8px;font-size:12px;border-bottom:1px solid #1f2226}
      .num{text-align:right}
      .foot{color:var(--sub);font-size:11px;margin-top:12px;text-align:center}
      @media(max-width:640px){.row1{grid-template-columns:repeat(2,1fr)}.row2{grid-template-columns:1fr}.stat .value{font-size:24px}header{flex-wrap:wrap;gap:8px}}
    </style>
    </head>
    <body>
    <div class="wrap">
      <header>
        <div class="brand"><span class="dot" id="dot"></span><h1>HardwareMonitor</h1><span class="tag">PRO · LAN</span></div>
        <div class="hbtns">
          <button onclick="act('lock')">🔒 锁屏</button>
          <button onclick="act('sleep')">💤 休眠</button>
        </div>
      </header>
      <div id="time">等待数据…</div>
      <div class="row1">
        <div class="panel stat"><div class="ptitle">CPU 占用</div><div class="value" id="cpu">--<small>%</small></div><div class="subv" id="cpuSub"></div><canvas class="spark" id="cpuSpark"></canvas></div>
        <div class="panel stat"><div class="ptitle">内存</div><div class="value" id="mem">--<small>%</small></div><div class="subv" id="memSub"></div><canvas class="spark" id="memSpark"></canvas></div>
        <div class="panel stat"><div class="ptitle">磁盘已用</div><div class="value" id="disk">--<small>%</small></div><div class="subv"></div><canvas class="spark" id="diskSpark"></canvas></div>
        <div class="panel stat"><div class="ptitle">芯片温度</div><div class="value" id="temp">--<small>°C</small></div><div class="subv" id="gpuSub"></div><canvas class="spark" id="tempSpark"></canvas></div>
        <div class="panel stat"><div class="ptitle">电池</div><div class="value" id="batt">--<small>%</small></div><div class="subv" id="battSub"></div><canvas class="spark" id="battSpark"></canvas></div>
        <div class="panel stat"><div class="ptitle">网络下行</div><div class="value" id="down">--<small>MB/s</small></div><div class="subv"></div><canvas class="spark" id="downSpark"></canvas></div>
        <div class="panel stat"><div class="ptitle">网络上行</div><div class="value" id="up">--<small>MB/s</small></div><div class="subv"></div><canvas class="spark" id="upSpark"></canvas></div>
      </div>
      <div class="row2">
        <div class="panel"><div class="ptitle">CPU / 内存 历史<span class="legend"><i style="background:var(--green)"></i>CPU<i style="background:var(--blue)"></i>内存</span></div><canvas class="chart" id="chart1"></canvas></div>
        <div class="panel"><div class="ptitle">网络吞吐<span class="legend"><i style="background:var(--blue)"></i>下行<i style="background:var(--orange)"></i>上行</span></div><canvas class="chart" id="chart2"></canvas></div>
      </div>
      <div class="row2">
        <div class="panel" style="grid-column:1 / -1"><div class="ptitle">进程 TOP 5</div>
          <table><thead><tr><th>进程</th><th class="num">CPU %</th><th class="num">内存 MB</th></tr></thead><tbody id="procs"></tbody></table>
        </div>
      </div>
      <div class="foot">HardwareMonitor Pro · 局域网远程监控 · 每 2 秒刷新</div>
    </div>
    <script>
      var MAXPTS=120;
      var H={cpu:[],mem:[],disk:[],temp:[],batt:[],down:[],up:[]};
      function pushH(k,v){H[k].push(v==null?null:v);if(H[k].length>MAXPTS){H[k].shift();}}
      function setup(c){var dpr=window.devicePixelRatio||1;var w=c.clientWidth,h=c.clientHeight;if(!w||!h){return null;}if(c.width!==Math.round(w*dpr)||c.height!==Math.round(h*dpr)){c.width=Math.round(w*dpr);c.height=Math.round(h*dpr);}var ctx=c.getContext('2d');ctx.setTransform(dpr,0,0,dpr,0,0);return{ctx:ctx,w:w,h:h};}
      function drawLine(ctx,arr,w,mx,color,top,bot){ctx.strokeStyle=color;ctx.lineWidth=1.5;ctx.beginPath();var started=false;for(var i=0;i<arr.length;i++){var v=arr[i];if(v==null){started=false;continue;}var x=arr.length>1?i/(arr.length-1)*w:0;var y=bot-(Math.min(v,mx)/mx)*(bot-top);if(!started){ctx.moveTo(x,y);started=true;}else{ctx.lineTo(x,y);}}ctx.stroke();}
      function spark(id,arr,color){var c=document.getElementById(id);if(!c){return;}var s=setup(c);if(!s){return;}var ctx=s.ctx,w=s.w,h=s.h;ctx.clearRect(0,0,w,h);var vals=[];for(var i=0;i<arr.length;i++){if(arr[i]!=null){vals.push(arr[i]);}}if(vals.length<2){return;}var mx=Math.max.apply(null,vals)*1.25;if(mx<=0){mx=1;}var top=4,bot=h-2;
        ctx.beginPath();var started=false;for(var i=0;i<arr.length;i++){var v=arr[i];if(v==null){started=false;continue;}var x=arr.length>1?i/(arr.length-1)*w:0;var y=bot-(Math.min(v,mx)/mx)*(bot-top);if(!started){ctx.moveTo(x,y);started=true;}else{ctx.lineTo(x,y);}}
        ctx.strokeStyle=color;ctx.lineWidth=1.5;ctx.stroke();
        ctx.lineTo(w,h);ctx.lineTo(0,h);ctx.closePath();ctx.globalAlpha=0.15;ctx.fillStyle=color;ctx.fill();ctx.globalAlpha=1;}
      function bigchart(id,series,fixedMax,unit){var c=document.getElementById(id);if(!c){return;}var s=setup(c);if(!s){return;}var ctx=s.ctx,w=s.w,h=s.h;ctx.clearRect(0,0,w,h);var padR=unit?44:30;var plotW=w-padR;var mx=fixedMax||1;
        if(!fixedMax){var all=[];for(var k=0;k<series.length;k++){var dd=series[k].data;for(var i=0;i<dd.length;i++){if(dd[i]!=null){all.push(dd[i]);}}}if(all.length<2){return;}mx=Math.max.apply(null,all)*1.2;if(mx<=0){mx=1;}}
        var top=8,bot=h-14;
        ctx.font='10px -apple-system,sans-serif';ctx.fillStyle='#8e8ea0';ctx.strokeStyle='#24272b';ctx.lineWidth=1;ctx.textAlign='right';
        var fr=fixedMax?[0,.25,.5,.75,1]:[0,.5,1];
        for(var g=0;g<fr.length;g++){var gy=bot-(bot-top)*fr[g];ctx.beginPath();ctx.moveTo(0,gy);ctx.lineTo(plotW,gy);ctx.stroke();var gv=mx*fr[g];var label=unit?(gv>=10?gv.toFixed(0):gv.toFixed(1)):Math.round(gv);ctx.fillText(label,w-4,gy+3);}
        ctx.textAlign='left';ctx.fillText('-4min',0,h-2);ctx.textAlign='right';ctx.fillText('now',plotW,h-2);
        for(var k=0;k<series.length;k++){drawLine(ctx,series[k].data,plotW,mx,series[k].color,top,bot);}}
      function fmt(n){return (n==null||isNaN(n))?'--':n.toFixed(0);}
      function setStat(id,v,unit,color){var el=document.getElementById(id);el.innerHTML=fmt(v)+'<small>'+unit+'</small>';el.style.color=color;}
      function c3(v,a,b){return v<a?'#73bf69':(v<b?'#fade2a':'#f2495c');}
      function tick(){
        fetch('/api/status').then(function(r){return r.json();}).then(function(d){
          if(!d.ok){throw new Error('no data');}
          document.getElementById('dot').className='dot ok';
          pushH('cpu',d.cpu);pushH('mem',d.memPercent);pushH('disk',d.diskPercent);pushH('temp',d.cpuTemp);pushH('batt',d.battery);pushH('down',d.netDown);pushH('up',d.netUp);
          setStat('cpu',d.cpu,'%',c3(d.cpu,70,85));
          setStat('mem',d.memPercent,'%',c3(d.memPercent,70,85));
          setStat('disk',d.diskPercent,'%',c3(d.diskPercent,70,85));
          document.getElementById('memSub').textContent=d.memUsed.toFixed(1)+' / '+d.memTotal.toFixed(1)+' GB';
          if(d.cpuTemp==null){setStat('temp',null,'°C','#8e8ea0');}else{setStat('temp',d.cpuTemp,'°C',c3(d.cpuTemp,50,70));}
          document.getElementById('gpuSub').textContent=d.gpuTemp==null?'GPU 温度不可用':'GPU '+fmt(d.gpuTemp)+' °C';
          if(d.battery==null){setStat('batt',null,'%','#8e8ea0');}else{setStat('batt',d.battery,'%',d.battery>30?'#73bf69':(d.battery>15?'#fade2a':'#f2495c'));}
          document.getElementById('battSub').textContent=d.charging?'⚡ 正在充电':'使用电池';
          document.getElementById('down').innerHTML=(d.netDown||0).toFixed(2)+'<small>MB/s</small>';
          document.getElementById('up').innerHTML=(d.netUp||0).toFixed(2)+'<small>MB/s</small>';
          spark('cpuSpark',H.cpu,'#5794f2');spark('memSpark',H.mem,'#b877d9');spark('diskSpark',H.disk,'#fade2a');spark('tempSpark',H.temp,'#ff9830');spark('battSpark',H.batt,'#73bf69');spark('downSpark',H.down,'#5794f2');spark('upSpark',H.up,'#ff9830');
          bigchart('chart1',[{data:H.cpu,color:'#73bf69'},{data:H.mem,color:'#5794f2'}],100,'');
          bigchart('chart2',[{data:H.down,color:'#5794f2'},{data:H.up,color:'#ff9830'}],null,'MB/s');
          var p='';var ps=d.procs||[];for(var i=0;i<ps.length;i++){p+='<tr><td>'+ps[i].name+'</td><td class="num">'+fmt(ps[i].cpu)+'</td><td class="num">'+fmt(ps[i].memMB)+'</td></tr>';}
          document.getElementById('procs').innerHTML=p||'<tr><td colspan="3" style="color:#8e8ea0">无数据</td></tr>';
          document.getElementById('time').textContent='实时监控 · 更新于 '+new Date().toLocaleTimeString();
        }).catch(function(){document.getElementById('dot').className='dot err';document.getElementById('time').textContent='连接中断，正在重试…';});
      }
      function act(a){fetch('/api/action',{method:'POST',body:'action='+a}).then(function(){document.getElementById('time').textContent='已发送「'+(a==='lock'?'锁屏':'休眠')+'」指令';});}
      tick();setInterval(tick,2000);window.addEventListener('resize',tick);
    </script>
    </body>
    </html>
    """
}
