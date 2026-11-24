// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 nuschpl. CallLift: https://github.com/nuschpl/CallLift
// Live statistics window for CallLift (opened from the menu; updates twice per second while visible).
import AppKit
import AVFoundation
import CoreAudio

final class StatsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var timer: Timer?
    private let text = NSTextField(labelWithString: "")
    private let level = NSLevelIndicator()
    private let limiter = NSLevelIndicator()
    private weak var app: AppDelegate?
    private var peakHold: Float = 0, peakHoldAt = Date.distantPast

    init(app: AppDelegate) { self.app = app }

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.update() }
        update()
    }

    func windowWillClose(_ n: Notification) { timer?.invalidate(); timer = nil }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "CallLift statistics"; w.isReleasedWhenClosed = false; w.delegate = self; w.center()
        for ind in [level, limiter] {
            ind.levelIndicatorStyle = .continuousCapacity
            ind.minValue = 0; ind.maxValue = 60
            ind.translatesAutoresizingMaskIntoConstraints = false
        }
        level.warningValue = 1000; level.criticalValue = 1000      // colour is set per update from the voice verdict
        level.numberOfTickMarks = 7; level.numberOfMajorTickMarks = 7; level.tickMarkPosition = .below  // every 10 dB
        limiter.maxValue = 12; limiter.warningValue = 3; limiter.criticalValue = 6
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.lineBreakMode = .byWordWrapping; text.maximumNumberOfLines = 0
        text.translatesAutoresizingMaskIntoConstraints = false
        let l1 = NSTextField(labelWithString: "Speech level to the call app (50 ms, like Zoom's meter; −60…0 dBFS)")
        let l2 = NSTextField(labelWithString: "Limiter gain reduction (0…12 dB)")
        for l in [l1, l2] { l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor; l.translatesAutoresizingMaskIntoConstraints = false }
        let v = NSView(); w.contentView = v
        [l1, level, l2, limiter, text].forEach(v.addSubview)
        NSLayoutConstraint.activate([
            l1.topAnchor.constraint(equalTo: v.topAnchor, constant: 14), l1.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            level.topAnchor.constraint(equalTo: l1.bottomAnchor, constant: 4), level.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            level.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16), level.heightAnchor.constraint(equalToConstant: 24),
            l2.topAnchor.constraint(equalTo: level.bottomAnchor, constant: 10), l2.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            limiter.topAnchor.constraint(equalTo: l2.bottomAnchor, constant: 4), limiter.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            limiter.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16), limiter.heightAnchor.constraint(equalToConstant: 16),
            text.topAnchor.constraint(equalTo: limiter.bottomAnchor, constant: 14), text.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            text.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16), text.bottomAnchor.constraint(lessThanOrEqualTo: v.bottomAnchor, constant: -14),
        ])
        window = w
    }

    private func update() {
        guard let app else { return }
        let ctl = app.ctl
        var lines: [String] = []
        let state: String = {
            if ctl.stalled { return "NO AUDIO from the microphone" }
            switch ctl.state {
            case .idle: return "idle (no app is listening to BlackHole 2ch)"
            case .active(let n): return "active: \(n) → BlackHole 2ch"
            case .lost(let n): return "MUTED: \(n) disconnected"
            case .error(let e): return "problem: \(e)"
            }
        }()
        lines.append("State          \(state)")
        lines.append("Microphone     \(ctl.sourceName)")
        lines.append("Boost          +\(Int(ctl.gainDB)) dB, limiter ceiling −1 dBFS")
        lines.append("Listening      \(ctl.readers.isEmpty ? "–" : ctl.readers.joined(separator: ", "))")
        if let t = ctl.lastStartSeconds { lines.append(String(format: "Mic start      %.2f s (Bluetooth call-mode switch)", t)) }
        if let p = ctl.pipe {
            let s = p.stats
            let peak = app.lastPeak, minG = app.lastMinGain
            if peak > peakHold || Date().timeIntervalSince(peakHoldAt) > 2 { peakHold = peak; peakHoldAt = Date() }
            let pdb = peak > 0 ? 20 * log10(peak) : -99
            let hdb = peakHold > 0 ? 20 * log10(peakHold) : -99
            let red = minG < 1 ? -20 * log10(minG) : 0
            let rdbBar = app.lastRms > 0 ? 20 * log10(app.lastRms) : -99
            level.doubleValue = Double(max(0, rdbBar + 60)); limiter.doubleValue = Double(red)
            switch app.voice {                                  // same colours as the menu bar icon / Zoom zones
            case .silent: level.fillColor = .systemGray
            case .quiet: level.fillColor = .systemYellow
            case .good: level.fillColor = .systemGreen
            case .loud: level.fillColor = .systemOrange
            }
            lines.append("")
            lines.append(String(format: "Formats        %.0f Hz %d ch → %.0f Hz %d ch", p.srcRate, p.srcChannels, p.dstRate, p.dstChannels))
            lines.append(String(format: "Output peak    %.1f dBFS (2 s hold %.1f)", pdb, hdb))
            let rdb = app.lastRms > 0 ? 20 * log10(app.lastRms) : -99
            let q: String = { switch app.voice { case .silent: return "not talking"; case .quiet: return "TOO QUIET"; case .good: return "good"; case .loud: return "TOO LOUD" } }()
            lines.append(String(format: "Speech level   %.1f dBFS (50 ms)  → %@   [good ≥ %.0f, voice ≥ %.0f]", rdb, q, ctl.goodDB, Controller.voicedDB))
            lines.append(String(format: "Limiter        %@", red > 0.1 ? String(format: "−%.1f dB", red) : "not acting"))
            lines.append(String(format: "Delay          ~%.0f ms (buffer %.1f ms + device buffers)", p.latencyMs + 7, p.latencyMs))
            lines.append(String(format: "Clock drift    %+.0f ppm correction", p.correctionPPM))
            lines.append("Dropouts       \(s.underruns.load(ordering: .relaxed))   resyncs \(s.resyncs.load(ordering: .relaxed))   overflow \(p.ring.overflow.load(ordering: .relaxed))")
            lines.append("Blocks         in \(s.inBlocks.load(ordering: .relaxed))   out \(s.outBlocks.load(ordering: .relaxed))")
        } else {
            level.doubleValue = 0; limiter.doubleValue = 0
        }
        if ctl.micPermission != .authorized { lines.append(""); lines.append("⚠︎ Microphone access is not granted to CallLift") }
        text.stringValue = lines.joined(separator: "\n")
    }
}
