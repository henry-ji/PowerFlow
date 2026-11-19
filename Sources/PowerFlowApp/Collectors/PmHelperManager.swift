import Foundation

@MainActor
final class PmHelperManager: ObservableObject {
    enum State: Equatable { case off, authorizing, on }

    @Published private(set) var state: State = .off
    @Published private(set) var statusNote: String?

    static let pidPath = "/tmp/powerflow-helper.pid"
    static let stopPath = "/tmp/powerflow-helper.stop"
    static let installDir = "/Library/Application Support/PowerFlow"
    static let label = "local.powerflow.pmhelper"
    static let plistPath = "/Library/LaunchDaemons/local.powerflow.pmhelper.plist"

    private var timer: Timer?

    var autoEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "PMHelperAutoEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "PMHelperAutoEnabled") }
    }

    func startMonitoring() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard state != .authorizing else { return }
        let stopping = FileManager.default.fileExists(atPath: Self.stopPath)
        state = Self.helperAlive() && !stopping ? .on : .off
    }

    static func helperAlive() -> Bool {
        guard let text = try? String(contentsOfFile: pidPath, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    func setEnabled(_ on: Bool) {
        autoEnabled = on
        if on { enable() } else { disable() }
    }

    func enable() {
        guard state != .authorizing else { return }
        if Self.helperAlive() {
            try? FileManager.default.removeItem(atPath: Self.stopPath)
            state = .on
            statusNote = nil
            return
        }
        guard let script = Self.scriptSource() else {
            state = .off
            autoEnabled = false
            statusNote = "缺少 pm-helper.sh 资源，无法安装守护进程"
            return
        }
        state = .authorizing
        statusNote = nil
        let dest = Self.installDir + "/pm-helper.sh"
        let shell = """
        mkdir -p '\(Self.installDir)' && cp '\(script)' '\(dest)' && chmod 755 '\(dest)' && cat > '\(Self.plistPath)' <<'PLIST'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        <key>Label</key><string>\(Self.label)</string>
        <key>ProgramArguments</key><array><string>/bin/bash</string><string>\(dest)</string></array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><true/>
        <key>StandardOutPath</key><string>/tmp/powerflow-helper.out</string>
        <key>StandardErrorPath</key><string>/tmp/powerflow-helper.out</string>
        </dict>
        </plist>
        PLIST
        chown root:wheel '\(Self.plistPath)' && chmod 644 '\(Self.plistPath)' && rm -f '\(Self.stopPath)' && (launchctl bootout system/\(Self.label) 2>/dev/null || true) && launchctl bootstrap system '\(Self.plistPath)' && echo ok
        """
        runPrivileged(shell) { ok, out in
            if ok {
                self.state = Self.helperAlive() && !FileManager.default.fileExists(atPath: Self.stopPath) ? .on : .off
                self.statusNote = self.state == .on ? nil : "守护进程未启动，查看 /tmp/powerflow-helper.out"
            } else {
                self.handleAuthFailure(out)
            }
        }
    }

    func uninstall() {
        guard state != .authorizing else { return }
        state = .authorizing
        let shell = "(launchctl bootout system/\(Self.label) 2>/dev/null || true) && rm -f '\(Self.plistPath)' '\(Self.installDir)/pm-helper.sh' '\(Self.stopPath)' && echo ok"
        runPrivileged(shell) { ok, out in
            if ok {
                self.autoEnabled = false
                self.state = .off
                self.statusNote = "实测守护进程已卸载"
            } else {
                self.handleAuthFailure(out)
            }
        }
    }

    private func handleAuthFailure(_ out: String) {
        state = .off
        autoEnabled = false
        let lowered = out.lowercased()
        statusNote = lowered.contains("canceled") || lowered.contains("cancelled")
            ? "已取消管理员授权，实测未开启"
            : "授权失败：" + String(out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    private func runPrivileged(_ shell: String, completion: @escaping (Bool, String) -> Void) {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script \"" + escaped + "\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", apple]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [weak self] proc in
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                completion(proc.terminationStatus == 0 && out.contains("ok"), out)
            }
        }
        do {
            try process.run()
        } catch {
            state = .off
            autoEnabled = false
            statusNote = "无法启动 osascript"
        }
    }

    func disable() {
        FileManager.default.createFile(atPath: Self.stopPath, contents: Data())
        state = .off
    }

    static func scriptSource() -> String? {
        if let env = ProcessInfo.processInfo.environment["PF_PM_SCRIPT"],
           FileManager.default.fileExists(atPath: env) { return env }
        if let path = Bundle.main.resourceURL?.appendingPathComponent("pm-helper.sh").path,
           FileManager.default.fileExists(atPath: path) { return path }
        return nil
    }
}