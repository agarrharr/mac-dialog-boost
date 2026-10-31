import Foundation

let usage = """
Dialog Boost: turns the background down and the voices up for anything playing on this Mac.

Usage:
  mac-dialog-boost [--background PERCENT] [--hq] [--port PORT | --no-remote]
  mac-dialog-boost process INPUT OUTPUT [--background PERCENT] [--hq]

Options:
  --background PERCENT
                   How much of the original sound to keep under the voices (0-100, default 20).
  --hq             Use the "High Quality Voice" isolation model.
  --port PORT      Port for the phone remote (default 8737).
  --no-remote      Don't start the phone remote.

While running:
  ↑ / ↓  (or + / -)   more / less background
  b                    bypass (hear the original, to compare)
  m                    switch isolation model (Voice / High Quality Voice)
  q                    quit
"""

var arguments = Array(CommandLine.arguments.dropFirst())
let chain = DialogChain()

func takeOption(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    defer { arguments.removeSubrange(index...index + 1) }
    return arguments[index + 1]
}

func takeFlag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}

if takeFlag("--help") || takeFlag("-h") {
    print(usage)
    exit(0)
}
if let background = takeOption("--background") ?? takeOption("--cars") {  // --cars: the original F1-era name
    guard let value = Float(background) else { fputs("--background needs a number from 0 to 100\n", stderr); exit(2) }
    chain.backgroundPercent = value
}
chain.highQuality = takeFlag("--hq")
let port = takeOption("--port").flatMap { UInt16($0) } ?? 8737
let remotePort: UInt16? = takeFlag("--no-remote") ? nil : port

if arguments.first == "process" {
    guard arguments.count == 3 else { fputs(usage + "\n", stderr); exit(2) }
    do {
        try processFile(input: URL(fileURLWithPath: arguments[1]), output: URL(fileURLWithPath: arguments[2]), chain: chain)
        print("Wrote \(arguments[2])")
        exit(0)
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }
}
guard arguments.isEmpty else { fputs(usage + "\n", stderr); exit(2) }

runLive(chain: chain, remotePort: remotePort)
