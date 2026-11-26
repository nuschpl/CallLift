// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 nuschpl. CallLift: https://github.com/nuschpl/CallLift
// "How CallLift works" help window (opened from the menu).
import AppKit

final class HelpWindow: NSObject {
    private var window: NSWindow?

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func icon(_ symbol: String, _ color: NSColor?) -> NSAttributedString {
        var cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        cfg = cfg.applying(.init(paletteColors: color == nil ? [.labelColor] : [.white, color!]))
        let att = NSTextAttachment()
        att.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
        att.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)
        return NSAttributedString(attachment: att)
    }

    /// Render the help text to a PNG (for previews / docs).
    func render(to path: String) {
        if window == nil { build() }
        guard let sv = window?.contentView as? NSScrollView, let tv = sv.documentView as? NSTextView else { return }
        tv.frame = NSRect(x: 0, y: 0, width: 600, height: 10)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let used = tv.layoutManager!.usedRect(for: tv.textContainer!)
        tv.frame = NSRect(x: 0, y: 0, width: 600, height: used.height + 30)
        let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.windowBackgroundColor.setFill(); tv.bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        tv.cacheDisplay(in: tv.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func build() {
        let body = NSFont.systemFont(ofSize: 13), bold = NSFont.boldSystemFont(ofSize: 13)
        let head = NSFont.boldSystemFont(ofSize: 15), mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let t = NSMutableAttributedString()
        func h(_ s: String) { t.append(NSAttributedString(string: "\n\(s)\n", attributes: [.font: head, .foregroundColor: NSColor.labelColor])) }
        func p(_ s: String) { t.append(NSAttributedString(string: s + "\n", attributes: [.font: body, .foregroundColor: NSColor.labelColor])) }
        func b(_ s: String) { t.append(NSAttributedString(string: s, attributes: [.font: bold, .foregroundColor: NSColor.labelColor])) }
        func m(_ s: String) { t.append(NSAttributedString(string: s + "\n", attributes: [.font: mono, .foregroundColor: NSColor.secondaryLabelColor])) }
        func row(_ sym: String, _ c: NSColor?, _ name: String, _ text: String) {
            t.append(icon(sym, c)); b("  \(name)  "); p(text)
        }

        t.append(NSAttributedString(string: "CallLift\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.labelColor]))
        p("Makes your microphone louder for Zoom (in Citrix) without cutting your speech.")

        h("How the sound flows")
        m("Jabra (or other mic) → CallLift: +boost, limiter → BlackHole 2ch → Zoom VDI plugin on this Mac → meeting")
        p("Your mic normally reaches Zoom about 10 dB below Zoom's \"green\" zone, and nothing in Zoom, Citrix or macOS can raise it. CallLift adds the missing gain (default +20 dB). A limiter catches the loudest moments at −1 dBFS so nothing distorts. Extra delay: about 22 ms (measured).")

        h("Required settings")
        p("• VDI Zoom → Audio → Microphone: BlackHole 2ch")
        p("• VDI Zoom → Microphone modes: Original sound for musicians, all three boxes unchecked (Zoom's Noise removal would trim word starts; CallLift supplies the level). Use Noise removal instead only if keyboard or room noise comes through.")
        p("• VDI Zoom → Advanced → Echo cancellation: Auto")
        p("• VDI Zoom → Speaker: your headset (or \"Same as system\") — never BlackHole 2ch")
        p("• Mac → System Settings → Sound → Input: the microphone you want to use (CallLift follows it)")
        p("• Zoom's \"Automatically adjust microphone volume\": off")
        p("• Mac → Control Center → Mic Mode → Zoom entry: Standard (Voice Isolation with Original sound costs about 10 dB)")

        h("Menu bar icon")
        row("mic.circle", nil, "Idle", "no app is listening to BlackHole 2ch; CallLift does not touch any microphone.")
        row("mic.circle.fill", .systemGray, "Starting", "the headset is switching to call mode (Bluetooth, about 2–4 s).")
        row("mic.circle.fill", .systemBlue, "Active", "Zoom is listening; you are not talking right now.")
        row("mic.circle.fill", .systemGreen, "Good", "you are talking and your level is good for Zoom.")
        row("mic.circle.fill", .systemYellow, "Too quiet", "speak up, move the mic closer, or raise the Boost.")
        row("mic.circle.fill", .systemOrange, "Too loud", "the limiter works hard: speak softer or lower the Boost.")
        row("mic.slash.circle.fill", .systemRed, "Muted / no access", "the mic disconnected, or CallLift has no microphone permission. Zoom gets silence.")
        row("exclamationmark.circle.fill", .systemRed, "Problem", "no audio from the mic, or BlackHole 2ch missing. Hover over the icon for details.")
        p("Hover over the icon for a one-line explanation. The colour follows your voice live, held for 1 s after you stop.")

        h("The limiter")
        p("The limiter makes sure your voice never goes above −1 dBFS (where digital clipping would start), however high the Boost is. It looks 2 ms ahead: just before a loud moment (a loud syllable, a \"p\", a laugh) it lowers the volume exactly as much as needed, then brings it back to the full boost over about 80 ms. Everything else gets the full boost.")
        p("How it sounds, by gain reduction (Statistics window: \"Limiter\" line and lower bar):")
        p("• 0–3 dB, occasionally: inaudible, only single peaks are touched.")
        p("• 3–6 dB, more often: slightly denser, radio-like; loud syllables lose a little punch, still natural.")
        p("• over 6 dB, often (orange icon): clearly compressed; loud and quiet speech sound almost equally loud, and you may hear \"pumping\" (the level dips after a loud word and comes back).")
        p("• Very high boost for your voice (e.g. +24 dB when you speak loudly): the limiter works almost all the time; you sound loud but flat. Still no clipping; very fast, deep reductions can sound slightly rough.")
        p("Rule of thumb: occasional orange on loud moments is fine. If the icon is orange most of the time you talk, lower the Boost one step. A red icon is never the limiter: it always means a problem (disconnected, no access, no audio).")

        h("When it runs")
        p("CallLift runs only while some app (Zoom) reads BlackHole 2ch, and stops 3 s after nobody does. So outside calls it never holds your Bluetooth headset in call mode, and music stays in good quality. It reconnects by itself after Zoom or Citrix reconnects, in any order.")

        h("Which microphone")
        p("By default CallLift follows the macOS default input (Sound settings or Control Center). If the microphone disappears (case, range, battery), CallLift does NOT switch to the MacBook mic: it sends silence, turns red and notifies you. When the headset comes back, it resumes automatically. To use another mic on purpose, pick it in the menu → Use microphone.")
        p("Note: \"muted\" means CallLift sends silence. Zoom's own mute button is not changed.")

        h("Menu")
        p("• Preset: ready-made settings for a tested setup. \"Mac + Citrix (Windows) + Zoom media plugin\" = BlackHole 2ch, follow default input, +20 dB, green from −20 dBFS. Any change of your own switches to Custom.")
        p("• Microphone: \"Follow macOS default input\" (normal), or \"Always use\" one fixed microphone. Use the fixed mode when the Mac's default input must be the virtual device itself (e.g. a Windows VM or Citrix without the media plugin, which only use the default input).")
        p("• Send to: the virtual device your call app uses as its microphone (default BlackHole 2ch). If it is missing, the menu offers the install command (Homebrew: brew install --cask blackhole-2ch).")
        p("• Boost: 0 to +24 dB (default +20, green in the menu). Below it usually too quiet for Zoom (yellow); +24 makes the limiter work more often (orange).")
        p("• Keep mic volumes at 100%: resets the input volume of your mic and of BlackHole 2ch if anything lowers it (Zoom's auto-volume did that once and the change stuck).")
        p("• Always active (testing): run even when nobody listens.")
        p("• Statistics… (⌘S): live level, limiter, delay, dropouts, clock drift.")
        p("• Microphone privacy settings…: opens the page where CallLift's microphone access is switched on/off.")

        h("If something goes wrong")
        p("• Red, no access: open the menu → Microphone privacy settings… and switch CallLift on.")
        p("• CallLift not running / quit: Zoom gets silence from BlackHole 2ch. Quick fix: VDI Zoom → Microphone: your headset directly.")
        p("• After a rebuild, macOS asks for microphone access again (the app is signed locally): allow it.")
        p("• Log: menu → Open log (~/Library/Logs/CallLift.log).")

        h("Removal")
        m("./install.sh --uninstall   (in the CallLift source folder)")
        p("Before removing: switch VDI Zoom's microphone back to your headset.")

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        tv.isEditable = false; tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 18, height: 12)
        tv.textStorage?.setAttributedString(t)
        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 640))
        sv.hasVerticalScroller = true; sv.documentView = tv; sv.drawsBackground = false
        tv.autoresizingMask = [.width]
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "How CallLift works"; w.isReleasedWhenClosed = false; w.contentView = sv; w.center()
        window = w
    }
}
