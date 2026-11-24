// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 nuschpl. CallLift: https://github.com/nuschpl/CallLift
// CallLift menu bar app: status icon + menu, notifications, log file.
import AppKit
import AVFoundation
import CoreAudio
import UserNotifications

final class Logger {
    let url: URL
    private let fh: FileHandle?
    private let df: DateFormatter = { let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return d }()
    init() {
        url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CallLift.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        fh = try? FileHandle(forWritingTo: url); fh?.seekToEndOfFile()
    }
    func log(_ s: String) {
        let line = "\(df.string(from: Date())) \(s)\n"
        fh?.write(line.data(using: .utf8)!)
        FileHandle.standardOutput.write(line.data(using: .utf8)!)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let logger = Logger()
    lazy var ctl = Controller(log: { [weak self] in self?.logger.log($0) })
    var item: NSStatusItem!
    let menu = NSMenu()
    var meterTimer: Timer?
    var lastPeak: Float = 0, lastMinGain: Float = 1, lastRms: Float = 0
    enum Voice { case silent, quiet, good, loud }
    var voice: Voice = .silent
    private var voiceUntil = Date.distantPast
    // thresholds on the 50 ms speech level (dBFS) of what Zoom receives, from the Zoom meter calibration

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        item.menu = menu
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        ctl.onStateChange = { [weak self] _, _ in self?.refreshTitle() }
        ctl.onNotice = { [weak self] in self?.notify($0) }
        // ask for microphone access right at launch (so the prompt appears at login, not in the middle of a call)
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { self.logger.log("microphone permission request answered: \(ok)"); self.ctl.tick(); self.refreshTitle() }
            }
        }
        ctl.start()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let p = self.ctl.pipe else { return }
            self.lastPeak = p.stats.takePeak(); self.lastMinGain = p.stats.takeMinGain(); self.lastRms = p.stats.takeRms()
            self.updateVoice()
            self.refreshTitle()
        }
        refreshTitle()
    }

    func applicationWillTerminate(_ n: Notification) { ctl.stopPipeline(); logger.log("quit") }

    // MARK: title

    /// Menu bar icon: colour = state (gray idle, orange starting, green active, red problem). No text.
    private var lastIconKey = ""
    func setIcon(_ b: NSStatusBarButton, symbol: String, color: NSColor?, tip: String) {
        let key = "\(symbol)|\(color?.description ?? "template")|\(tip)"
        if key == lastIconKey { return }                 // refreshed twice a second: only redraw on change
        lastIconKey = key
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "CallLift")!
        if let color {
            let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold).applying(.init(paletteColors: [.white, color]))
            let colored = img.withSymbolConfiguration(cfg)!; colored.isTemplate = false
            b.image = colored
        } else {
            let t = img.withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))!; t.isTemplate = true
            b.image = t
        }
        b.title = ""; b.toolTip = tip
    }

    /// Classify the last 0.5 s; keep a speaking colour for 1 s so it doesn't flicker between words.
    func updateVoice() {
        let rdb = lastRms > 0 ? 20 * log10(lastRms) : -120
        let reduction = lastMinGain < 1 ? -20 * log10(lastMinGain) : 0
        var now: Voice = .silent
        if reduction > Controller.loudReductionDB { now = .loud }
        else if rdb >= ctl.goodDB { now = .good }
        else if rdb >= Controller.voicedDB { now = .quiet }
        if now != .silent { voice = now; voiceUntil = Date().addingTimeInterval(1) }
        else if Date() > voiceUntil { voice = .silent }
    }

    func refreshTitle() {
        guard let b = item?.button else { return }
        let g = String(format: "+%.0f dB", ctl.gainDB)
        if ctl.micPermission == .denied || ctl.micPermission == .restricted {
            return setIcon(b, symbol: "mic.slash.circle.fill", color: .systemRed, tip: "CallLift has NO microphone access: you would be silent in Zoom")
        }
        if ctl.stalled { return setIcon(b, symbol: "exclamationmark.circle.fill", color: .systemRed, tip: "No audio from \(ctl.sourceName): Zoom gets silence") }
        switch ctl.state {
        case .idle:
            if ctl.isStarting { setIcon(b, symbol: "mic.circle.fill", color: .systemGray, tip: "Starting \(ctl.sourceName) (Bluetooth switching to call mode)") }
            else { setIcon(b, symbol: "mic.circle", color: nil, tip: "CallLift idle (\(g)): no app is listening to BlackHole 2ch") }
        case .active(let n):
            let base = "\(n) → Zoom, \(g)"
            switch voice {
            case .silent: setIcon(b, symbol: "mic.circle.fill", color: .systemBlue, tip: "CallLift active (not talking): \(base)")
            case .good: setIcon(b, symbol: "mic.circle.fill", color: .systemGreen, tip: "Good level: \(base)")
            case .quiet: setIcon(b, symbol: "mic.circle.fill", color: .systemYellow, tip: "Too quiet for Zoom: speak up or raise the boost (\(base))")
            case .loud: setIcon(b, symbol: "mic.circle.fill", color: .systemOrange, tip: "Too loud / too close: limiter working hard (\(base))")
            }
        case .lost(let n):
            setIcon(b, symbol: "mic.slash.circle.fill", color: .systemRed, tip: "\(n) disconnected: Zoom gets silence until it returns or you pick a mic")
        case .error(let e):
            setIcon(b, symbol: "exclamationmark.circle.fill", color: .systemRed, tip: "CallLift problem: \(e)")
        }
    }

    // MARK: menu

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        func info(_ s: String) { let i = NSMenuItem(title: s, action: nil, keyEquivalent: ""); i.isEnabled = false; m.addItem(i) }
        switch ctl.state {
        case .idle: info("Idle: no app is listening to BlackHole 2ch")
        case .active(let n): info("Active: \(n) → BlackHole 2ch")
        case .lost(let n): info("MUTED: \(n) disconnected")
        case .error(let e): info("Problem: \(e)")
        }
        if case .active = ctl.state {} else { info("Microphone: \(ctl.sourceName)") }
        let perm: String = { switch ctl.micPermission { case .authorized: return "granted"; case .denied: return "DENIED"; case .restricted: return "RESTRICTED"; default: return "not asked yet" } }()
        if ctl.micPermission != .authorized { info("⚠︎ Microphone access: \(perm)") }
        if ctl.stalled { info("⚠︎ No audio from the microphone (Zoom gets silence)") }
        m.addItem(.separator())

        // Preset
        let pre = NSMenuItem(title: "Preset", action: nil, keyEquivalent: ""); let psub = NSMenu()
        for p in Preset.all {
            let i = NSMenuItem(title: p.name, action: #selector(choosePreset(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = p.id; i.state = ctl.presetID == p.id ? .on : .off; i.toolTip = p.summary
            psub.addItem(i)
        }
        let cu = NSMenuItem(title: "Custom (your own changes)", action: nil, keyEquivalent: ""); cu.isEnabled = false
        cu.state = ctl.presetID == "custom" ? .on : .off; psub.addItem(cu)
        pre.submenu = psub; m.addItem(pre)

        // Microphone: follow macOS default, or a fixed one
        let mics = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: ""); let sub = NSMenu()
        let fol = NSMenuItem(title: "Follow macOS default input", action: #selector(followDefault), keyEquivalent: "")
        fol.target = self; fol.state = ctl.followDefault ? .on : .off; sub.addItem(fol)
        sub.addItem(.separator())
        let hdr = NSMenuItem(title: "Always use:", action: nil, keyEquivalent: ""); hdr.isEnabled = false; sub.addItem(hdr)
        for d in ctl.eligibleInputs() {
            let i = NSMenuItem(title: CA.name(d), action: #selector(chooseMic(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = NSNumber(value: d)
            i.state = CA.uid(d) == ctl.sourceUID ? (ctl.followDefault ? .mixed : .on) : .off
            sub.addItem(i)
        }
        mics.submenu = sub; m.addItem(mics)

        // Virtual device the boosted voice goes to
        let snk = NSMenuItem(title: "Send to: \(ctl.sinkName)", action: nil, keyEquivalent: ""); let ssub = NSMenu()
        let have = ctl.candidateSinks()
        for n in have {
            let i = NSMenuItem(title: n, action: #selector(chooseSink(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = n; i.state = n == ctl.sinkName ? .on : .off
            ssub.addItem(i)
        }
        if !have.contains(Controller.defaultSink) {
            if !have.isEmpty { ssub.addItem(.separator()) }
            let ins = NSMenuItem(title: "Install \(Controller.defaultSink)…", action: #selector(installSink), keyEquivalent: "")
            ins.target = self; ssub.addItem(ins)
        }
        snk.submenu = ssub; m.addItem(snk)

        let gain = NSMenuItem(title: "Boost", action: nil, keyEquivalent: ""); let gsub = NSMenu()
        for g in [0, 3, 6, 8, 10, 12, 15, 18, 20, 24] as [Float] {
            // colour guide: yellow = likely too quiet for Zoom, green = recommended, orange = limiter works often, red = heavy limiting
            let (dot, note): (NSColor, String) = {
                switch g {
                case 0: return (.systemGray, "  off")
                case ..<15: return (.systemYellow, "  usually too quiet for Zoom")
                case 15: return (.systemGreen, "  recommended")
                case ..<24: return (.systemOrange, "  louder, limiter works more often")
                default: return (.systemRed, "  very loud, heavy limiting")
                }
            }()
            let title = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: dot, .font: NSFont.menuFont(ofSize: 0)])
            title.append(NSAttributedString(string: g == 0 ? "0 dB" : "+\(Int(g)) dB", attributes: [.font: NSFont.menuFont(ofSize: 0)]))
            title.append(NSAttributedString(string: note, attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.menuFont(ofSize: 11)]))
            let i = NSMenuItem(title: g == 0 ? "Off (0 dB)" : "+\(Int(g)) dB", action: #selector(chooseGain(_:)), keyEquivalent: "")
            i.attributedTitle = title
            i.target = self; i.representedObject = NSNumber(value: g); i.state = g == ctl.gainDB ? .on : .off
            gsub.addItem(i)
        }
        gain.submenu = gsub; m.addItem(gain)

        let hold = NSMenuItem(title: "Keep mic volumes at 100%", action: #selector(toggleHold), keyEquivalent: "")
        hold.target = self; hold.state = ctl.holdVolumes ? .on : .off; m.addItem(hold)
        let always = NSMenuItem(title: "Always active (testing)", action: #selector(toggleAlways), keyEquivalent: "")
        always.target = self; always.state = ctl.alwaysActive ? .on : .off; m.addItem(always)
        m.addItem(.separator())
        let hp = NSMenuItem(title: "How CallLift works…", action: #selector(openHelp), keyEquivalent: "?"); hp.target = self; m.addItem(hp)
        let st = NSMenuItem(title: "Statistics…", action: #selector(openStats), keyEquivalent: "s"); st.target = self; m.addItem(st)
        let pv = NSMenuItem(title: "Microphone privacy settings…", action: #selector(openPrivacy), keyEquivalent: ""); pv.target = self; m.addItem(pv)
        let lg = NSMenuItem(title: "Open log", action: #selector(openLog), keyEquivalent: ""); lg.target = self; m.addItem(lg)
        let q = NSMenuItem(title: "Quit CallLift", action: #selector(quit), keyEquivalent: "q"); q.target = self; m.addItem(q)
    }

    @objc func choosePreset(_ i: NSMenuItem) { if let id = i.representedObject as? String, let p = Preset.find(id) { ctl.apply(p); refreshTitle() } }
    @objc func followDefault() { ctl.followSystemDefault() }
    @objc func chooseSink(_ i: NSMenuItem) { if let n = i.representedObject as? String { ctl.sinkName = n; ctl.log("virtual device set to \(n)") } }
    @objc func installSink() {
        let hint = Controller.installHint(for: Controller.defaultSink)
        let al = NSAlert()
        al.messageText = "\(Controller.defaultSink) is not installed"
        al.informativeText = hint + "\n\nCallLift sends your boosted voice to this virtual device; your call app uses it as its microphone."
        if Controller.brewPath != nil {
            al.addButton(withTitle: "Copy command"); al.addButton(withTitle: "Close")
            NSApp.activate(ignoringOtherApps: true)
            if al.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew install --cask \(Controller.defaultSink.lowercased().replacingOccurrences(of: " ", with: "-"))", forType: .string)
            }
        } else {
            al.addButton(withTitle: "Open BlackHole page"); al.addButton(withTitle: "Close")
            NSApp.activate(ignoringOtherApps: true)
            if al.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(URL(string: "https://github.com/ExistentialAudio/BlackHole")!) }
        }
    }
    @objc func chooseMic(_ i: NSMenuItem) { if let n = i.representedObject as? NSNumber { ctl.userChoose(AudioObjectID(n.uint32Value)) } }
    @objc func chooseGain(_ i: NSMenuItem) { if let n = i.representedObject as? NSNumber { ctl.gainDB = n.floatValue; ctl.log("boost set to \(n.floatValue) dB"); refreshTitle() } }
    @objc func toggleHold() { ctl.holdVolumes.toggle() }
    @objc func toggleAlways() { ctl.alwaysActive.toggle() }
    lazy var help = HelpWindow()
    @objc func openHelp() { help.show() }
    lazy var stats = StatsWindow(app: self)
    @objc func openStats() { stats.show() }
    @objc func openPrivacy() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }
    @objc func openLog() { NSWorkspace.shared.open(logger.url) }
    @objc func quit() { NSApp.terminate(nil) }

    func notify(_ text: String) {
        let c = UNMutableNotificationContent(); c.title = "CallLift"; c.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
