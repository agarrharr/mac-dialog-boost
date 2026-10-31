import Foundation

/// Starts the phone remote and prints its QR code. Everything here runs on the main queue.
func startRemote(port: UInt16, chain: CommentaryChain, booster: LiveBooster) throws -> RemoteServer {
    func state() -> RemoteServer.Response {
        let state: [String: Any] = [
            "cars": chain.carsPercent,
            "bypassed": chain.bypassed,
            "highQuality": chain.highQuality,
            "active": booster.isActive,
            "canControlPlayback": PlaybackKeys.hasPermission,
        ]
        return RemoteServer.Response(body: (try? JSONSerialization.data(withJSONObject: state)) ?? Data())
    }

    let server = try RemoteServer(port: port, token: remoteToken()) { path, query in
        switch path {
        case "/", "/index.html":
            return RemoteServer.Response(contentType: "text/html; charset=utf-8", body: Data(remotePageHTML.utf8))
        case "/api/state":
            break
        case "/api/cars":
            if let value = query["v"].flatMap(Float.init) { chain.carsPercent = value }
        case "/api/bypass":
            chain.bypassed.toggle()
        case "/api/model":
            chain.highQuality.toggle()
        case "/api/playpause":
            PlaybackKeys.playPause()
        case "/api/back":
            PlaybackKeys.back()
        case "/api/forward":
            PlaybackKeys.forward()
        default:
            return RemoteServer.Response(status: 404, contentType: "text/plain", body: Data("Not found".utf8))
        }
        return state()
    }
    server.start { error in
        FileHandle.standardOutput.write("\r\u{1B}[2KPhone remote stopped: \(error)\n".data(using: .utf8)!)
    }

    // Ask while someone is at the keyboard to answer the prompt.
    if isatty(STDIN_FILENO) != 0 { PlaybackKeys.requestPermission() }

    print("Phone remote: scan this with your phone's camera (phone and Mac on the same Wi-Fi)\n")
    if let qr = terminalQRCode(server.url) { print(qr) }
    print("\n  \(server.url)")
    if let ipURL = server.ipURL { print("  or \(ipURL)") }
    if !PlaybackKeys.hasPermission {
        print("  Play/pause from the phone needs Accessibility permission for your terminal app:")
        print("  System Settings → Privacy & Security → Accessibility")
    }
    print("")
    return server
}
