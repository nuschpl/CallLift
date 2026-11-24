// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 nuschpl. CallLift: https://github.com/nuschpl/CallLift
// CallLift entry point.
//   CallLift                              menu bar app (normal use)
//   CallLift --headless [--always] [--source NAME] [--gain DB] [--seconds N]   no UI, for automated tests
import AppKit
import Foundation

func argValue(_ k: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}
setvbuf(stdout, nil, _IOLBF, 0)

if let path = argValue("--render-help") {
    _ = NSApplication.shared
    HelpWindow().render(to: path); exit(0)
}
if CommandLine.arguments.contains("--headless") {
    let logger = Logger()
    let ctl = Controller(log: { logger.log($0) })
    if let g = argValue("--gain").flatMap(Float.init) { ctl.gainDB = g }
    if let s = argValue("--source") { ctl.forcedSourceName = s }
    if CommandLine.arguments.contains("--always") { ctl.alwaysActive = true }
    ctl.onStateChange = { new, old in logger.log("STATE \(old) -> \(new)") }
    ctl.onNotice = { logger.log("NOTICE \($0)") }
    ctl.start()
    let secs = argValue("--seconds").flatMap(Double.init) ?? 1e9
    let t0 = Date()
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        if let p = ctl.pipe {
            logger.log(String(format: "stats: fill %.1f ms corr %+.0f ppm underruns %d resyncs %d peak %.3f",
                              p.latencyMs, p.correctionPPM, p.stats.underruns.load(ordering: .relaxed),
                              p.stats.resyncs.load(ordering: .relaxed), p.stats.takePeak()))
        }
        if Date().timeIntervalSince(t0) > secs {
            if CommandLine.arguments.contains("--always") { ctl.alwaysActive = false }  // don't persist test flag
            ctl.stopPipeline(); exit(0)
        }
    }
    RunLoop.main.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
