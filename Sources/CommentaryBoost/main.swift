import Foundation

let usage = """
Commentary Boost: turns the cars down and the commentators up for anything playing on this Mac.

Usage:
  commentary-boost [--cars PERCENT] [--hq] [--port PORT | --no-remote]
  commentary-boost process INPUT OUTPUT [--cars PERCENT] [--hq]

Options:
  --cars PERCENT   How much of the original sound to keep under the voices (0-100, default 20).
  --hq             Use the "High Quality Voice" isolation model.
  --port PORT      Port for the phone remote (default 8737).
  --no-remote      Don't start the phone remote.

While running:
  ↑ / ↓  (or + / -)   more / less car sound
  b                    bypass (hear the original, to compare)
  m                    switch isolation model (Voice / High Quality Voice)
  q                    quit
"""

var arguments = Array(CommandLine.arguments.dropFirst())
let chain = CommentaryChain()

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
if let cars = takeOption("--cars") {
    guard let value = Float(cars) else { fputs("--cars needs a number from 0 to 100\n", stderr); exit(2) }
    chain.carsPercent = value
}
chain.highQuality = takeFlag("--hq")
let remotePort: UInt16? = takeFlag("--no-remote") ? nil : (takeOption("--port").flatMap { UInt16($0) } ?? 8737)

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
