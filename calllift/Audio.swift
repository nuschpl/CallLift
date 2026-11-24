// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 nuschpl. CallLift: https://github.com/nuschpl/CallLift
// CallLift audio core: source mic --(gain + limiter)--> lock-free ring --(drift-controlled resampler)--> BlackHole 2ch
// Two independent HAL IOProcs (no aggregate device, so the source may run at 16 kHz while BlackHole runs at 48 kHz).
import CoreAudio
import Foundation
import Synchronization

// MARK: - CoreAudio helpers

enum CA {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func addr(_ s: AudioObjectPropertySelector, _ sc: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: sc, mElement: el)
    }
    static func ids(_ o: AudioObjectID, _ s: AudioObjectPropertySelector, _ sc: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var a = addr(s, sc); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(o, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var arr = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(o, &a, 0, nil, &size, &arr) == noErr else { return [] }
        return arr
    }
    static func string(_ o: AudioObjectID, _ s: AudioObjectPropertySelector) -> String? {
        var a = addr(s); var v: Unmanaged<CFString>? = nil; var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(o, &a, 0, nil, &size, &v) == noErr, let s = v?.takeRetainedValue() else { return nil }
        return s as String
    }
    static func u32(_ o: AudioObjectID, _ s: AudioObjectPropertySelector, _ sc: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var a = addr(s, sc); var v: UInt32 = 0; var size: UInt32 = 4
        return AudioObjectGetPropertyData(o, &a, 0, nil, &size, &v) == noErr ? v : nil
    }
    static func i32(_ o: AudioObjectID, _ s: AudioObjectPropertySelector) -> Int32? {
        var a = addr(s); var v: Int32 = 0; var size: UInt32 = 4
        return AudioObjectGetPropertyData(o, &a, 0, nil, &size, &v) == noErr ? v : nil
    }
    static func f64(_ o: AudioObjectID, _ s: AudioObjectPropertySelector) -> Double? {
        var a = addr(s); var v: Float64 = 0; var size: UInt32 = 8
        return AudioObjectGetPropertyData(o, &a, 0, nil, &size, &v) == noErr ? v : nil
    }
    static func name(_ d: AudioObjectID) -> String { string(d, kAudioObjectPropertyName) ?? "?" }
    static func uid(_ d: AudioObjectID) -> String { string(d, kAudioDevicePropertyDeviceUID) ?? "" }
    static func devices() -> [AudioObjectID] { ids(system, kAudioHardwarePropertyDevices) }
    static func hasInput(_ d: AudioObjectID) -> Bool { !ids(d, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput).isEmpty }
    static func hasOutput(_ d: AudioObjectID) -> Bool { !ids(d, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput).isEmpty }
    static func device(named n: String) -> AudioObjectID? { devices().first { name($0) == n } }
    static func device(uid u: String) -> AudioObjectID? { devices().first { uid($0) == u } }
    static func defaultInput() -> AudioObjectID? { ids(system, kAudioHardwarePropertyDefaultInputDevice).first }
    static func isAlive(_ d: AudioObjectID) -> Bool { (u32(d, kAudioDevicePropertyDeviceIsAlive) ?? 0) != 0 && devices().contains(d) }
    static func sampleRate(_ d: AudioObjectID) -> Double { f64(d, kAudioDevicePropertyNominalSampleRate) ?? 0 }
    static func inputVolume(_ d: AudioObjectID) -> Float? {
        var a = addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, kAudioObjectPropertyElementMain)
        var v: Float32 = 0; var size: UInt32 = 4
        return AudioObjectGetPropertyData(d, &a, 0, nil, &size, &v) == noErr ? v : nil
    }
    @discardableResult static func setInputVolume(_ d: AudioObjectID, _ v: Float) -> Bool {
        var a = addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(d, &a, &settable) == noErr, settable.boolValue else { return false }
        var x = Float32(v)
        return AudioObjectSetPropertyData(d, &a, 0, nil, 4, &x) == noErr
    }
    @discardableResult static func setBufferFrames(_ d: AudioObjectID, _ n: UInt32) -> UInt32 {
        var a = addr(kAudioDevicePropertyBufferFrameSize); var v = n
        _ = AudioObjectSetPropertyData(d, &a, 0, nil, 4, &v)
        return u32(d, kAudioDevicePropertyBufferFrameSize) ?? n
    }
    static func channels(_ d: AudioObjectID, _ sc: AudioObjectPropertyScope) -> Int {
        var a = addr(kAudioDevicePropertyStreamConfiguration, sc); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(d, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16); defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(d, &a, 0, nil, &size, raw) == noErr else { return 0 }
        let abl = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return abl.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
    /// Processes (other than us) currently reading audio input from device `d`.
    static func inputReaders(of d: AudioObjectID) -> [(pid: Int32, bundle: String)] {
        let me = getpid()
        return ids(system, kAudioHardwarePropertyProcessObjectList).compactMap { p in
            guard (u32(p, kAudioProcessPropertyIsRunningInput) ?? 0) != 0 else { return nil }
            let pid = i32(p, kAudioProcessPropertyPID) ?? -1
            guard pid != me else { return nil }
            guard ids(p, kAudioProcessPropertyDevices, kAudioObjectPropertyScopeInput).contains(d) else { return nil }
            return (pid, string(p, kAudioProcessPropertyBundleID) ?? "")
        }
    }
}

// MARK: - Lock-free single-producer / single-consumer ring of Float samples

final class Ring: @unchecked Sendable {
    let cap: Int
    private let buf: UnsafeMutablePointer<Float>
    private let w = Atomic<Int>(0)   // total samples written (producer only)
    private let r = Atomic<Int>(0)   // total samples consumed (consumer only)
    let overflow = Atomic<Int>(0)
    init(capacity: Int) {
        cap = capacity; buf = .allocate(capacity: capacity); buf.initialize(repeating: 0, count: capacity)
    }
    deinit { buf.deallocate() }
    func write(_ p: UnsafePointer<Float>, _ n: Int) {
        let wi = w.load(ordering: .relaxed), ri = r.load(ordering: .acquiring)
        let k = min(n, cap - (wi - ri))
        for i in 0..<k { buf[(wi + i) % cap] = p[i] }
        w.store(wi + k, ordering: .releasing)
        if k < n { overflow.add(n - k, ordering: .relaxed) }
    }
    var available: Int { w.load(ordering: .acquiring) - r.load(ordering: .relaxed) }
    @inline(__always) func peek(_ i: Int) -> Float { buf[(r.load(ordering: .relaxed) + i) % cap] }
    func advance(_ k: Int) { r.store(r.load(ordering: .relaxed) + k, ordering: .releasing) }
}

// MARK: - Statistics shared with the UI (written on RT threads, read on main)

final class Stats: @unchecked Sendable {
    let inBlocks = Atomic<Int>(0), outBlocks = Atomic<Int>(0)
    let underruns = Atomic<Int>(0), resyncs = Atomic<Int>(0)
    let peakBits = Atomic<UInt32>(0)          // max |output| since last read (Float bit pattern)
    let limitBits = Atomic<UInt32>(0)         // min limiter gain since last read
    let rmsBits = Atomic<UInt32>(0)           // max short-term (50 ms) RMS of the output since last read
    let fillMilli = Atomic<Int>(0)            // ring fill in source samples * 1000
    let epsBits = Atomic<UInt64>(0)           // current resampler correction (Double bits)
    func takePeak() -> Float { Float(bitPattern: peakBits.exchange(0, ordering: .relaxed)) }
    func takeRms() -> Float { Float(bitPattern: rmsBits.exchange(0, ordering: .relaxed)) }
    func takeMinGain() -> Float { let b = limitBits.exchange(Float(1).bitPattern, ordering: .relaxed); return b == 0 ? 1 : Float(bitPattern: b) }
}

// MARK: - The pipeline

final class Pipeline: @unchecked Sendable {
    let source: AudioObjectID, sink: AudioObjectID
    let srcRate: Double, dstRate: Double
    let srcChannels: Int, dstChannels: Int
    let ring: Ring
    let stats = Stats()
    private var inProc: AudioDeviceIOProcID?, outProc: AudioDeviceIOProcID?
    private let rtQueue = DispatchQueue(label: "calllift.rt", qos: .userInteractive)

    // parameters (written by main thread, read by RT threads)
    let gainBits = Atomic<UInt32>(Float(1).bitPattern)
    let muted = Atomic<Bool>(false)

    // producer (input thread) state
    private var limGain: Float = 1
    private let ceiling: Float = 0.891          // -1 dBFS
    private let look: Int                        // limiter look-ahead in samples
    private var delay: [Float]; private var dIdx = 0
    private let release: Float
    private var rmsEnv: Float = 0                // 50 ms mean-square envelope of the output (like a level meter)
    private let rmsCoef: Float
    private var mono: UnsafeMutablePointer<Float>
    private let monoCap = 8192

    // consumer (output thread) state
    private var pos: Double = 0, xm1: Float = 0
    private var primed = false
    private var integ: Double = 0
    let targetFill: Double                      // in source samples
    // anti-imaging low-pass after upsampling (two cascaded biquads = 4th-order Butterworth), only if srcRate < dstRate
    private var lpOn = false
    private var lb: [(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float)] = []
    private var lz: [(z1: Float, z2: Float)] = [(0, 0), (0, 0)]

    init?(source: AudioObjectID, sink: AudioObjectID, gainDB: Float, log: @escaping (String) -> Void) {
        self.source = source; self.sink = sink
        srcRate = CA.sampleRate(source); dstRate = CA.sampleRate(sink)
        srcChannels = CA.channels(source, kAudioObjectPropertyScopeInput)
        dstChannels = CA.channels(sink, kAudioObjectPropertyScopeOutput)
        guard srcRate > 0, dstRate > 0, srcChannels > 0, dstChannels > 0 else { log("pipeline: bad formats"); return nil }
        // small device buffers: ~5 ms each
        let sb = CA.setBufferFrames(source, UInt32(max(32, srcRate * 0.005)))
        let ob = CA.setBufferFrames(sink, UInt32(max(64, dstRate * 0.005)))
        // target fill: one source block + one output block (in source samples) + 5 ms margin
        targetFill = Double(sb) + Double(ob) * srcRate / dstRate + srcRate * 0.005
        ring = Ring(capacity: Int(srcRate * 2))
        look = max(1, Int(srcRate * 0.002))
        delay = [Float](repeating: 0, count: look)
        release = Float(1 - exp(-1 / (srcRate * 0.08)))   // 80 ms release
        rmsCoef = Float(1 - exp(-1 / (srcRate * 0.05)))   // 50 ms level-meter time constant
        mono = .allocate(capacity: monoCap)
        gainBits.store(Float(pow(10, gainDB / 20)).bitPattern, ordering: .relaxed)
        if srcRate < dstRate * 0.99 {
            let fc = 0.45 * srcRate, w0 = 2 * Double.pi * fc / dstRate
            for q in [0.5412, 1.3066] {                       // Butterworth Q pair for 4th order
                let al = sin(w0) / (2 * q), cw = cos(w0), a0 = 1 + al
                lb.append((Float((1 - cw) / 2 / a0), Float((1 - cw) / a0), Float((1 - cw) / 2 / a0),
                           Float(-2 * cw / a0), Float((1 - al) / a0)))
            }
            lpOn = true
        }
        log(String(format: "pipeline: %@ %.0f Hz %d ch (buf %d) -> %@ %.0f Hz %d ch (buf %d), target fill %.1f ms",
                   CA.name(source), srcRate, srcChannels, sb, CA.name(sink), dstRate, dstChannels, ob, targetFill / srcRate * 1000))
    }
    deinit { mono.deallocate() }

    func setGain(db: Float) { gainBits.store(Float(pow(10, db / 20)).bitPattern, ordering: .relaxed) }
    var latencyMs: Double { Double(stats.fillMilli.load(ordering: .relaxed)) / 1000 / srcRate * 1000 }
    var correctionPPM: Double { Double(bitPattern: stats.epsBits.load(ordering: .relaxed)) * 1e6 }

    func start() -> Bool {
        var st = AudioDeviceCreateIOProcIDWithBlock(&inProc, source, rtQueue) { [unowned self] _, inData, _, _, _ in
            self.produce(inData)
        }
        guard st == noErr, let ip = inProc else { return false }
        st = AudioDeviceCreateIOProcIDWithBlock(&outProc, sink, rtQueue) { [unowned self] _, _, _, outData, _ in
            self.consume(outData)
        }
        guard st == noErr, let op = outProc else { AudioDeviceDestroyIOProcID(source, ip); inProc = nil; return false }
        guard AudioDeviceStart(sink, op) == noErr, AudioDeviceStart(source, ip) == noErr else { stop(); return false }
        return true
    }

    func stop() {
        if let ip = inProc { AudioDeviceStop(source, ip); AudioDeviceDestroyIOProcID(source, ip); inProc = nil }
        if let op = outProc { AudioDeviceStop(sink, op); AudioDeviceDestroyIOProcID(sink, op); outProc = nil }
    }

    // input thread: mix to mono, gain, look-ahead limiter, push to ring
    private func produce(_ inData: UnsafePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        guard let first = abl.first, let p0 = first.mData else { return }
        let ch = Int(first.mNumberChannels)
        let frames = min(monoCap, Int(first.mDataByteSize) / (4 * max(1, ch)))
        let src = p0.assumingMemoryBound(to: Float.self)
        let g = Float(bitPattern: gainBits.load(ordering: .relaxed))
        let mute = muted.load(ordering: .relaxed)
        var peak: Float = 0, minG: Float = 1, maxEnv: Float = 0
        for f in 0..<frames {
            // microphones are mono: take the first channel (averaging would attenuate multi-channel devices)
            let x = src[f * ch] * g
            // limiter: gain computed from the newest sample, applied to the delayed one (look-ahead)
            let a = abs(x)
            let target: Float = a > ceiling ? ceiling / a : 1
            if target < limGain { limGain = target } else { limGain += (1 - limGain) * release }
            let y = delay[dIdx] * limGain
            delay[dIdx] = x; dIdx = (dIdx + 1) % look
            let out = mute ? 0 : max(-ceiling, min(ceiling, y))
            mono[f] = out
            peak = max(peak, abs(out)); minG = min(minG, limGain)
            rmsEnv += (out * out - rmsEnv) * rmsCoef; maxEnv = max(maxEnv, rmsEnv)
        }
        ring.write(mono, frames)
        stats.inBlocks.add(1, ordering: .relaxed)
        // publish meters (keep max peak / min gain until read)
        var cur = stats.peakBits.load(ordering: .relaxed)
        while Float(bitPattern: cur) < peak {
            let (ok, now) = stats.peakBits.compareExchange(expected: cur, desired: peak.bitPattern, ordering: .relaxed)
            if ok { break }; cur = now
        }
        let rms = sqrtf(maxEnv)
        var cr = stats.rmsBits.load(ordering: .relaxed)
        while Float(bitPattern: cr) < rms {
            let (ok, now) = stats.rmsBits.compareExchange(expected: cr, desired: rms.bitPattern, ordering: .relaxed)
            if ok { break }; cr = now
        }
        var cg = stats.limitBits.load(ordering: .relaxed)
        while cg == 0 || Float(bitPattern: cg) > minG {
            let (ok, now) = stats.limitBits.compareExchange(expected: cg, desired: minG.bitPattern, ordering: .relaxed)
            if ok { break }; cg = now
        }
    }

    // output thread: drift-controlled cubic resampler from ring to BlackHole (all channels get the same mono signal)
    private func consume(_ outData: UnsafeMutablePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(outData)
        guard let first = abl.first, let p0 = first.mData else { return }
        let ch = Int(first.mNumberChannels)
        let frames = Int(first.mDataByteSize) / (4 * max(1, ch))
        let out = p0.assumingMemoryBound(to: Float.self)
        let avail = Double(ring.available)
        stats.outBlocks.add(1, ordering: .relaxed)
        if !primed {
            if avail >= targetFill { primed = true; integ = 0 } else {
                for i in 0..<(frames * ch) { out[i] = 0 }; return
            }
        }
        // bounded latency: if we fell far behind (e.g. after a hiccup), jump back to target
        if avail > targetFill * 4 + Double(frames) * srcRate / dstRate {
            ring.advance(Int(avail - targetFill)); pos = 0; integ = 0
            stats.resyncs.add(1, ordering: .relaxed)
        }
        // PI controller on fill level -> tiny ratio correction (drift between the two device clocks)
        let err = (Double(ring.available) - pos - targetFill) / targetFill
        integ = max(-0.004, min(0.004, integ + err * 2e-6))
        let eps = max(-0.005, min(0.005, err * 1e-3 + integ))
        let step = srcRate / dstRate * (1 + eps)
        stats.epsBits.store(eps.bitPattern, ordering: .relaxed)
        stats.fillMilli.store(Int((Double(ring.available) - pos) * 1000), ordering: .relaxed)
        var f = 0
        while f < frames {
            if ring.available < 3 {        // underrun: fill the rest with silence, re-prime
                for i in (f * ch)..<(frames * ch) { out[i] = 0 }
                stats.underruns.add(1, ordering: .relaxed); primed = false; return
            }
            let x0 = ring.peek(0), x1 = ring.peek(1), x2 = ring.peek(2)
            let t = Float(pos)
            // 4-point Catmull-Rom (cubic Hermite) interpolation between x0 and x1
            let c0 = x0, c1 = 0.5 * (x1 - xm1)
            let c2 = xm1 - 2.5 * x0 + 2 * x1 - 0.5 * x2
            let c3 = 0.5 * (x2 - xm1) + 1.5 * (x0 - x1)
            var y = ((c3 * t + c2) * t + c1) * t + c0
            if lpOn {                                          // transposed direct form II
                for k in 0..<2 {
                    let c = lb[k]; let o = c.b0 * y + lz[k].z1
                    lz[k].z1 = c.b1 * y - c.a1 * o + lz[k].z2
                    lz[k].z2 = c.b2 * y - c.a2 * o
                    y = o
                }
            }
            for c in 0..<ch { out[f * ch + c] = y }
            f += 1
            pos += step
            while pos >= 1 { xm1 = ring.peek(0); ring.advance(1); pos -= 1; if ring.available < 3 { break } }
        }
    }
}
