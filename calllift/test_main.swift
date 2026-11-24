// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 nuschpl. CallLift: https://github.com/nuschpl/CallLift
// Headless test driver for the audio core (not part of the app).
// Usage: pipetest --source "BlackHole 16ch" --sink "BlackHole 2ch" --gain 10 --seconds 30
import CoreAudio
import Foundation

func arg(_ k: String, _ d: String) -> String {
    if let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count { return CommandLine.arguments[i + 1] }
    return d
}
setvbuf(stdout, nil, _IOLBF, 0)
let srcName = arg("--source", "BlackHole 16ch"), sinkName = arg("--sink", "BlackHole 2ch")
let gain = Float(arg("--gain", "10"))!, secs = Double(arg("--seconds", "20"))!
guard let src = CA.device(named: srcName), let sink = CA.device(named: sinkName) else { print("device not found"); exit(1) }
if let r = Double(arg("--srcrate", "0")), r > 0 {
    var a = CA.addr(kAudioDevicePropertyNominalSampleRate); var v = Float64(r)
    let st = AudioObjectSetPropertyData(src, &a, 0, nil, 8, &v)
    Thread.sleep(forTimeInterval: 1)
    print("set \(srcName) rate -> \(CA.sampleRate(src)) (status \(st))")
}
guard let p = Pipeline(source: src, sink: sink, gainDB: gain, log: { print($0) }) else { exit(1) }
guard p.start() else { print("start failed"); exit(1) }
let t0 = Date()
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
    let s = p.stats
    print(String(format: "t=%4.0fs in=%d out=%d fill=%.1f ms corr=%+.0f ppm underruns=%d resyncs=%d overflow=%d peak=%.3f minLimGain=%.3f",
                 Date().timeIntervalSince(t0), s.inBlocks.load(ordering: .relaxed), s.outBlocks.load(ordering: .relaxed),
                 p.latencyMs, p.correctionPPM, s.underruns.load(ordering: .relaxed), s.resyncs.load(ordering: .relaxed),
                 p.ring.overflow.load(ordering: .relaxed), s.takePeak(), s.takeMinGain()))
    if Date().timeIntervalSince(t0) >= secs { p.stop(); print("stopped"); exit(0) }
}
RunLoop.main.run()
