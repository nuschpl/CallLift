// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 nuschpl. CallLift: https://github.com/nuschpl/CallLift
// Latency probe: timestamps the first sample of each click as it appears on two devices' INPUTS
// (host clock), and prints the difference. Usage: latprobe "BlackHole 16ch" "BlackHole 2ch" <seconds>
import CoreAudio
import Foundation
setvbuf(stdout, nil, _IOLBF, 0)
let a = CommandLine.arguments
guard a.count >= 4, let d1 = CA.device(named: a[1]), let d2 = CA.device(named: a[2]), let secs = Double(a[3]) else { print("usage"); exit(1) }
var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
func hostSec(_ t: UInt64) -> Double { Double(t) * Double(tb.numer) / Double(tb.denom) / 1e9 }
final class Probe: @unchecked Sendable {
    let name: String, rate: Double; var lastHit = 0.0; var hits: [Double] = []
    init(_ n: String, _ r: Double) { name = n; rate = r }
}
let p1 = Probe(a[1], CA.sampleRate(d1)), p2 = Probe(a[2], CA.sampleRate(d2))
let q = DispatchQueue(label: "probe", qos: .userInteractive)
var ids: [(AudioObjectID, AudioDeviceIOProcID)] = []
for (d, p) in [(d1, p1), (d2, p2)] {
    var proc: AudioDeviceIOProcID?
    AudioDeviceCreateIOProcIDWithBlock(&proc, d, q) { _, inData, inTime, _, _ in
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        guard let b = abl.first, let m = b.mData else { return }
        let ch = Int(b.mNumberChannels), n = Int(b.mDataByteSize) / 4 / max(1, ch)
        let s = m.assumingMemoryBound(to: Float.self)
        let t0 = hostSec(inTime.pointee.mHostTime)
        for i in 0..<n where abs(s[i * ch]) > 0.05 {
            let t = t0 + Double(i) / p.rate
            if t - p.lastHit > 0.5 { p.hits.append(t) }
            p.lastHit = t; break
        }
    }
    AudioDeviceStart(d, proc!); ids.append((d, proc!))
}
DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
    for (d, pr) in ids { AudioDeviceStop(d, pr); AudioDeviceDestroyIOProcID(d, pr) }
    print("clicks seen: \(p1.name) \(p1.hits.count), \(p2.name) \(p2.hits.count)")
    var diffs: [Double] = []
    for h in p1.hits { if let m = p2.hits.first(where: { $0 > h && $0 - h < 0.5 }) { diffs.append((m - h) * 1000) } }
    for (i, d) in diffs.enumerated() { print(String(format: "click %d: %.1f ms", i + 1, d)) }
    if !diffs.isEmpty {
        let s = diffs.sorted()
        print(String(format: "LATENCY through CallLift core: median %.1f ms, min %.1f, max %.1f (n=%d)", s[s.count / 2], s.first!, s.last!, s.count))
    }
    exit(0)
}
RunLoop.main.run()
