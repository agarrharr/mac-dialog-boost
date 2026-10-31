import Foundation

/// Terminal front end for live mode: a status line with level meters and single-key controls.
func runLive(chain: DialogChain, remotePort: UInt16?) -> Never {
    // The status line is written straight to the file handle; keep print() output in order with it.
    setvbuf(stdout, nil, _IOLBF, 0)

    let booster: LiveBooster
    do {
        booster = try LiveBooster(chain: chain)
        try booster.start()
    } catch {
        fputs("Couldn't start: \(error)\n", stderr)
        exit(1)
    }

    var original = termios()
    tcgetattr(STDIN_FILENO, &original)
    var raw = original
    raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &raw)

    var remote: RemoteServer?
    func quit() -> Never {
        booster.stop()
        remote?.stop()
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
        print("\nStopped. Your Mac's audio is back to normal.")
        exit(0)
    }

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let signals = [SIGINT, SIGTERM].map { DispatchSource.makeSignalSource(signal: $0, queue: .main) }
    for source in signals {
        source.setEventHandler { quit() }
        source.resume()
    }

    if let remotePort {
        do {
            remote = try startRemote(port: remotePort, chain: chain, booster: booster)
        } catch {
            print("Phone remote unavailable: \(error)\n")
        }
    }

    print("""
    Dialog Boost → \(booster.outputName)
    ↑/↓ background louder/quieter · b bypass · m isolation model · q quit

    """)

    let started = Date()
    var shownPermissionHelp = false
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: .milliseconds(100))
    timer.setEventHandler {
        do {
            try booster.activateIfReady()
        } catch {
            FileHandle.standardOutput.write("\r\u{1B}[2KCouldn't take over the audio: \(error)\n".data(using: .utf8)!)
            quit()
        }
        if !booster.isActive, !shownPermissionHelp, Date().timeIntervalSince(started) > 6 {
            shownPermissionHelp = true
            FileHandle.standardOutput.write(("\r\u{1B}[2K" + permissionHelp + "\n").data(using: .utf8)!)
        }

        let input = booster.inputPeak, output = booster.outputPeak
        booster.inputPeak = 0
        booster.outputPeak = 0
        let mode = !booster.isActive ? "waiting for audio… (your sound is unchanged)"
            : chain.bypassed ? "BYPASSED (original sound)"
            : chain.highQuality ? "High Quality Voice" : "Voice"
        let line = "Background \(bar(chain.backgroundPercent / 100, width: 10)) \(String(format: "%3.0f", chain.backgroundPercent))%"
            + "   in \(meter(input))  out \(meter(output))   \(mode)"
            + (ProcessInfo.processInfo.environment["DIALOG_BOOST_DEBUG"] != nil ? "   [\(booster.callbackCount) \(booster.inputLayout)]" : "")
        FileHandle.standardOutput.write(("\r\u{1B}[2K" + line).data(using: .utf8)!)
    }
    timer.resume()

    Thread {
        var escape: [UInt8] = []
        while true {
            var byte: UInt8 = 0
            let count = read(STDIN_FILENO, &byte, 1)
            if count == 0 { return }  // no keyboard (stdin closed); keep running until a signal
            guard count == 1 else { continue }
            if !escape.isEmpty || byte == 0x1B {
                escape.append(byte)
                guard escape.count == 3 else { continue }
                let key = escape[2]
                escape.removeAll()
                if key == UInt8(ascii: "A") { DispatchQueue.main.async { chain.backgroundPercent += 5 } }
                if key == UInt8(ascii: "B") { DispatchQueue.main.async { chain.backgroundPercent -= 5 } }
                continue
            }
            DispatchQueue.main.async {
                switch Character(UnicodeScalar(byte)) {
                case "+", "=": chain.backgroundPercent += 5
                case "-", "_": chain.backgroundPercent -= 5
                case "b", "B": chain.bypassed.toggle()
                case "m", "M": chain.highQuality.toggle()
                case "q", "Q": quit()
                default: break
                }
            }
        }
    }.start()

    dispatchMain()
}

private let permissionHelp = """
No audio is reaching Dialog Boost yet. If something is playing, your terminal app needs
permission to hear system audio. macOS doesn't ask for this automatically when you run a
command-line tool, so add it by hand:

  1. System Settings → Privacy & Security → Screen & System Audio Recording
  2. Under "System Audio Recording Only", click + and add your terminal app (e.g. Terminal)
  3. Quit and reopen the terminal app, then run mac-dialog-boost again

Nothing is muted while this message shows. Press q to quit.
"""

private func bar(_ fraction: Float, width: Int) -> String {
    let filled = Int((fraction * Float(width)).rounded())
    return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
}

/// A small dBFS meter: empty below -60 dB, full at 0 dB.
private func meter(_ peak: Float) -> String {
    let db = peak > 0 ? 20 * log10(peak) : -100
    return bar(min(max((db + 60) / 60, 0), 1), width: 8)
}
