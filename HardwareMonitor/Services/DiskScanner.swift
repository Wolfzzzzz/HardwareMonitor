import Foundation

/// 磁盘大文件扫描（Premium 专属）
/// 后台扫描主目录，收集体积最大的文件（≥50MB）
final class DiskScanner {
    struct BigFile: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let size: Int64
    }

    private var cancelled = false

    /// 扫描主目录，返回 Top N 大文件（后台执行）
    func scan(top n: Int) async -> [BigFile] {
        cancelled = false
        let home = NSHomeDirectory()
        let fm = FileManager.default
        var files: [BigFile] = []

        func walk(_ dir: String) {
            guard !cancelled else { return }
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for item in items {
                guard !cancelled else { return }
                let path = dir + "/" + item
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    if item == "Library" || item == "node_modules" || item == ".Trash" || item == "Applications" { continue }
                    walk(path)
                } else if let attr = try? fm.attributesOfItem(atPath: path),
                          let size = attr[.size] as? Int64, size >= 50_000_000 {
                    files.append(BigFile(name: item, path: path, size: size))
                }
            }
        }

        await Task.detached(priority: .utility) { walk(home) }.value
        files.sort { $0.size > $1.size }
        return Array(files.prefix(n))
    }

    func cancel() { cancelled = true }
}
