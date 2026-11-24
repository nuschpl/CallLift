// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 nuschpl. CallLift: https://github.com/nuschpl/CallLift
// CallLift controller: decides WHEN to run (someone reads BlackHole 2ch), WHICH mic to use
// (follows the macOS default input, but never follows a forced switch after a disconnect),
// holds input volumes at 100%, and reports state to the UI.
import AVFoundation
import CoreAudio
import Foundation

enum BoostState: Equatable {
    case idle                    // nobody (Zoom) is reading BlackHole 2ch
    case active(String)          // boosting this source
    case lost(String)            // source disappeared -> silent until it returns or user picks another
    case error(String)
}

/// A preset bundles what CallLift itself controls for one tested setup.
struct Preset {
    let id: String, name: String, summary: String
    let sinkName: String, followDefault: Bool, gainDB: Float, goodDB: Float
    static let all: [Preset] = [
        Preset(id: "zoom-citrix", name: "Mac + Citrix (Windows) + Zoom media plugin",
               summary: "Tested 2026-11: Zoom VDI plugin on the Mac reads the virtual device; Zoom mic = BlackHole 2ch, Noise removal on.",
               sinkName: "BlackHole 2ch", followDefault: true, gainDB: 20, goodDB: -20),
    ]
    static func find(_ id: String) -> Preset? { all.first { $0.id == id } }
}

final class Controller {
    static let defaultSink = "BlackHole 2ch"
    /// virtual device the boosted voice is written to (the conferencing app uses it as its microphone)
    var sinkName: String { didSet { defaults.set(sinkName, forKey: "sinkName"); markCustom(); restartPipeline(); tick() } }
    /// true: follow the macOS default input; false: always use the fixed microphone (sourceUID)
    var followDefault: Bool { didSet { defaults.set(followDefault, forKey: "followDefault"); markCustom() } }
    /// speech level (dBFS, 50 ms) from which the icon turns green; calibrated against Zoom's meter
    var goodDB: Float { didSet { defaults.set(goodDB, forKey: "goodDB"); markCustom() } }
    static let voicedDB: Float = -45, loudReductionDB: Float = 6
    private(set) var presetID: String { didSet { defaults.set(presetID, forKey: "presetID") } }
    private var applyingPreset = false
    private var sinkNotified = false
    let defaults: UserDefaults = Bundle.main.bundleIdentifier == "io.github.nuschpl.CallLift" ? .standard : UserDefaults(suiteName: "io.github.nuschpl.CallLift")!
    var gainDB: Float { didSet { defaults.set(gainDB, forKey: "gainDB"); pipe?.setGain(db: gainDB); markCustom() } }
    var holdVolumes: Bool { didSet { defaults.set(holdVolumes, forKey: "holdVolumes"); enforceVolumes() } }
    var alwaysActive: Bool { didSet { defaults.set(alwaysActive, forKey: "alwaysActive"); tick() } }
    var forcedSourceName: String?           // test / CLI override

    private(set) var state: BoostState = .idle { didSet { if state != oldValue { onStateChange?(state, oldValue) } } }
    private(set) var sourceUID: String?      // the mic we use (or want back, when lost)
    private(set) var readers: [String] = []
    var pipe: Pipeline?
    var onStateChange: ((BoostState, BoostState) -> Void)?
    var onNotice: ((String) -> Void)?
    let log: (String) -> Void

    private var timer: Timer?
    private var idleSince: Date?
    private var pendingDefault: DispatchWorkItem?
    private var lastDevices: Set<String> = []          // UIDs of input devices seen last time
    private var rateListener: (AudioObjectID, AudioObjectPropertyListenerBlock)?
    private var starting = false { didSet { if starting != oldValue { onStateChange?(state, state) } } }  // Bluetooth call-mode switch in progress
    var isStarting: Bool { starting }
    private var lastInBlocks = -1, stallTicks = 0, stallRestarted = false
    private(set) var stalled = false      // input callbacks stopped while active (hung Bluetooth link)
    private var permissionNotified = false
    private(set) var lastStartSeconds: Double?
    var micPermission: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    init(log: @escaping (String) -> Void) {
        self.log = log
        let preset = Preset.all[0]
        gainDB = defaults.object(forKey: "gainDB") as? Float ?? preset.gainDB
        sinkName = defaults.string(forKey: "sinkName") ?? preset.sinkName
        followDefault = defaults.object(forKey: "followDefault") as? Bool ?? preset.followDefault
        goodDB = defaults.object(forKey: "goodDB") as? Float ?? preset.goodDB
        presetID = defaults.string(forKey: "presetID") ?? preset.id
        holdVolumes = defaults.object(forKey: "holdVolumes") as? Bool ?? true
        alwaysActive = defaults.object(forKey: "alwaysActive") as? Bool ?? false
        sourceUID = defaults.string(forKey: "sourceUID")
    }

    // MARK: eligible sources

    func isEligible(_ d: AudioObjectID) -> Bool {
        guard CA.hasInput(d) else { return false }
        let n = CA.name(d)
        if n == sinkName || n == "ZoomAudioDevice" { return false }
        if CA.uid(d).hasPrefix("io.github.nuschpl.calllift") { return false }
        return true
    }
    func eligibleInputs() -> [AudioObjectID] { CA.devices().filter(isEligible) }

    // MARK: lifecycle

    func start() {
        lastDevices = Set(eligibleInputs().map(CA.uid))
        if sourceUID == nil || CA.device(uid: sourceUID!) == nil,
           let d = CA.defaultInput(), isEligible(d) { setSource(CA.uid(d), reason: "initial default input") }
        var dev = CA.addr(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(CA.system, &dev, .main) { [weak self] _, _ in self?.devicesChanged() }
        var def = CA.addr(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectAddPropertyListenerBlock(CA.system, &def, .main) { [weak self] _, _ in self?.defaultChanged() }
        // react immediately when an app starts/stops using audio (instead of waiting for the 1 s poll)
        var procs = CA.addr(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(CA.system, &procs, .main) { [weak self] _, _ in self?.tick() }
        if let sink = CA.device(named: sinkName) {
            var run = CA.addr(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectAddPropertyListenerBlock(sink, &run, .main) { [weak self] _, _ in self?.tick() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        log("controller started: gain \(gainDB) dB, hold volumes \(holdVolumes), source \(sourceName)")
        tick()
    }

    var sourceName: String {
        if let f = forcedSourceName { return f }
        guard let u = sourceUID else { return "none" }
        if let d = CA.device(uid: u) { return CA.name(d) }
        return defaults.string(forKey: "sourceName") ?? u
    }

    private func setSource(_ uid: String, reason: String) {
        guard uid != sourceUID || { if case .lost = state { return true }; return false }() else { return }
        sourceUID = uid
        defaults.set(uid, forKey: "sourceUID")
        if let d = CA.device(uid: uid) { defaults.set(CA.name(d), forKey: "sourceName") }
        log("source -> \(sourceName) (\(reason))")
        restartPipeline()
    }

    /// Explicit user choice from the menu (also clears a "lost" state).
    func userChoose(_ d: AudioObjectID) {
        followDefault = false
        if case .lost = state { state = .idle }
        setSource(CA.uid(d), reason: "chosen in menu")
        tick()
    }

    // MARK: device events

    private func devicesChanged() {
        let now = Set(eligibleInputs().map(CA.uid))
        let gone = lastDevices.subtracting(now), came = now.subtracting(lastDevices)
        lastDevices = now
        if let s = sourceUID, gone.contains(s) {
            log("source \(sourceName) disappeared -> muted until it returns")
            stopPipeline()
            state = .lost(sourceName)
            onNotice?("\(sourceName) disconnected. CallLift now sends silence to Zoom (Zoom's own mute button is not changed). It resumes when \(sourceName) is back, or pick a mic in the CallLift menu.")
        }
        if let s = sourceUID, came.contains(s), case .lost = state {
            log("source \(sourceName) is back")
            state = .idle
            onNotice?("\(sourceName) is back. CallLift resumed.")
            tick()
        }
    }

    /// Default input changed. Wait 1.2 s (device-gone events may arrive after this one), then decide:
    /// follow only if the previous source still exists (= a deliberate user switch).
    private func defaultChanged() {
        pendingDefault?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, let d = CA.defaultInput() else { return }
            let name = CA.name(d)
            guard self.followDefault else { self.log("default input -> \(name) ignored (fixed microphone mode)"); return }
            if case .lost = self.state { self.log("default input -> \(name) ignored (source lost, not following an automatic switch)"); return }
            guard self.isEligible(d) else { self.log("default input -> \(name) ignored (not a usable mic)"); return }
            if let s = self.sourceUID, CA.device(uid: s) == nil {
                self.log("default input -> \(name) ignored (previous source vanished)"); return
            }
            self.setSource(CA.uid(d), reason: "macOS default input changed")
        }
        pendingDefault = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
    }

    // MARK: activity (runs every second)

    func tick() {
        guard let sink = CA.device(named: sinkName) else {
            stopPipeline()
            state = .error("Virtual device \"\(sinkName)\" not found")
            if !sinkNotified {
                sinkNotified = true
                log("virtual device \(sinkName) not found")
                onNotice?("Virtual device \"\(sinkName)\" is missing. " + Controller.installHint(for: sinkName))
            }
            return
        }
        if sinkNotified { sinkNotified = false; log("virtual device \(sinkName) available") }
        readers = CA.inputReaders(of: sink).map { $0.bundle.isEmpty ? "pid \($0.pid)" : $0.bundle }
        let wanted = alwaysActive || !readers.isEmpty
        if case .lost = state { return }
        // 1) microphone permission (an ad-hoc signed rebuild needs a new approval; denial = silent mic, no error)
        if micPermission == .denied || micPermission == .restricted {
            if pipe != nil { stopPipeline() }
            state = .error("Microphone access denied for CallLift")
            if !permissionNotified {
                permissionNotified = true
                log("microphone permission denied")
                onNotice?("Microphone access for CallLift is OFF. You would be SILENT in Zoom. Open the CallLift menu → Microphone privacy settings.")
            }
            return
        } else if permissionNotified { permissionNotified = false; if case .error = state { state = .idle } }
        if wanted {
            idleSince = nil
            if pipe == nil && !starting { startPipeline() }
            enforceVolumes()
            checkStall()
        } else if pipe != nil {
            if idleSince == nil { idleSince = Date() }
            if Date().timeIntervalSince(idleSince!) > 3 { log("nobody reads \(sinkName) -> idle"); stopPipeline(); state = .idle }
        } else { state = .idle }
    }

    private func sourceDevice() -> AudioObjectID? {
        if let f = forcedSourceName { return eligibleInputs().first { CA.name($0) == f } }
        guard let u = sourceUID else { return nil }
        return CA.device(uid: u)
    }

    private func startPipeline() {
        guard let src = sourceDevice(), let sink = CA.device(named: sinkName) else {
            state = .error("no microphone selected"); return
        }
        guard let p = Pipeline(source: src, sink: sink, gainDB: gainDB, log: log) else {
            state = .error("could not set up audio for \(CA.name(src))"); log("pipeline setup failed"); return
        }
        starting = true
        let t0 = Date(), name = CA.name(src)
        // start off the main thread: opening a Bluetooth mic switches it to call mode, which can block for seconds
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = p.start()
            let dt = Date().timeIntervalSince(t0)
            DispatchQueue.main.async {
                guard let self else { p.stop(); return }
                self.starting = false
                self.lastStartSeconds = dt
                guard ok else { self.state = .error("could not start audio for \(name)"); self.log("pipeline start failed after \(String(format: "%.2f", dt)) s"); return }
                let stillWanted: Bool = { if case .lost = self.state { return false }; return self.alwaysActive || !self.readers.isEmpty }()
                guard stillWanted, self.sourceDevice() == src else { p.stop(); self.log("start finished but no longer wanted -> stopped"); self.tick(); return }
                self.pipe = p
                self.state = .active(name)
                self.log("active: \(name) -> \(self.sinkName), +\(self.gainDB) dB, readers \(self.readers), mic start took \(String(format: "%.2f", dt)) s")
                self.attachRateListener(src)
            }
        }
    }

    private func attachRateListener(_ src: AudioObjectID) {
        // rate changes on the source (e.g. Jabra music 44.1k <-> call 16k) need a restart
        var r = CA.addr(kAudioDevicePropertyNominalSampleRate)
        let blk: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.pipe?.source == src else { return }
            self.log("source sample rate changed -> restart"); self.restartPipeline()
        }
        AudioObjectAddPropertyListenerBlock(src, &r, .main, blk)
        rateListener = (src, blk)
    }

    /// 2) input watchdog: if the mic stops delivering callbacks while active, warn and try one restart.
    private func checkStall() {
        guard let p = pipe else { lastInBlocks = -1; stallTicks = 0; return }
        let n = p.stats.inBlocks.load(ordering: .relaxed)
        if n == lastInBlocks { stallTicks += 1 } else { stallTicks = 0; if stalled { stalled = false; stallRestarted = false; log("microphone delivers audio again"); onNotice?("\(sourceName) delivers audio again."); onStateChange?(state, state) } }
        lastInBlocks = n
        if stallTicks >= 3 && !stalled {
            stalled = true
            log("no audio callbacks from \(sourceName) for 3 s")
            onNotice?("No audio from \(sourceName) for 3 s. Zoom gets silence. Trying to restart the microphone…")
            onStateChange?(state, state)
            if !stallRestarted { stallRestarted = true; restartPipeline() }
        }
    }

    func stopPipeline() {
        if let (d, blk) = rateListener {
            var r = CA.addr(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(d, &r, .main, blk); rateListener = nil
        }
        pipe?.stop(); pipe = nil
    }
    private func restartPipeline() { let was = pipe != nil; stopPipeline(); if was { tick() } }

    /// Keep source and BlackHole 2ch input volume at 100% (Zoom's auto-volume can lower them silently).
    private func enforceVolumes() {
        guard holdVolumes else { return }
        for d in [sourceDevice(), CA.device(named: sinkName)].compactMap({ $0 }) {
            if let v = CA.inputVolume(d), v < 0.999 {
                if CA.setInputVolume(d, 1) {
                    log(String(format: "input volume of %@ was %.0f%% -> reset to 100%%", CA.name(d), v * 100))
                    onNotice?(String(format: "%@ input volume was %.0f%%, reset to 100%%.", CA.name(d), v * 100))
                }
            }
        }
    }

    // MARK: presets, follow mode, virtual device

    private func markCustom() {
        guard !applyingPreset, presetID != "custom", let p = Preset.find(presetID) else { return }
        let same = p.sinkName == sinkName && p.followDefault == followDefault && p.gainDB == gainDB && p.goodDB == goodDB
        if !same { presetID = "custom" }
    }

    func apply(_ p: Preset) {
        applyingPreset = true
        sinkName = p.sinkName; followDefault = p.followDefault; gainDB = p.gainDB; goodDB = p.goodDB
        applyingPreset = false
        presetID = p.id
        log("preset applied: \(p.name)")
        if followDefault, let d = CA.defaultInput(), isEligible(d) { setSource(CA.uid(d), reason: "preset: follow default input") }
    }

    /// Switch back to following the macOS default input (and pick it up right away).
    func followSystemDefault() {
        followDefault = true
        if let d = CA.defaultInput(), isEligible(d) { setSource(CA.uid(d), reason: "follow macOS default input") }
        tick()
    }

    /// Output-capable devices that can carry the boosted voice (virtual devices first).
    func candidateSinks() -> [String] {
        let names = CA.devices().filter { CA.hasOutput($0) && CA.hasInput($0) }.map(CA.name)
        return Array(Set(names)).sorted { a, b in
            let va = a.hasPrefix("BlackHole"), vb = b.hasPrefix("BlackHole")
            return va != vb ? va : a < b
        }
    }

    static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func installHint(for sink: String) -> String {
        guard sink.hasPrefix("BlackHole") else { return "Check that the device exists in Audio MIDI Setup, or pick another one in the CallLift menu." }
        let cask = sink.lowercased().replacingOccurrences(of: " ", with: "-")       // "blackhole-2ch"
        if brewPath != nil { return "Install it with: brew install --cask \(cask), then log out and in (or: sudo killall coreaudiod)." }
        return "Install BlackHole from https://github.com/ExistentialAudio/BlackHole (or install Homebrew, then: brew install --cask \(cask))."
    }
}
