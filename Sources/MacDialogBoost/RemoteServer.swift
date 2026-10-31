import Foundation
import Network
import SystemConfiguration

/// A deliberately tiny HTTP server for the phone remote. Every request must carry the access code
/// (`?k=…`) that's embedded in the QR code, so other people on the Wi-Fi can't change your sound.
/// Everything runs on the main queue, alongside the rest of the UI.
final class RemoteServer {
    struct Response {
        var status = 200
        var contentType = "application/json"
        var body = Data()
    }

    typealias Handler = (_ path: String, _ query: [String: String]) -> Response

    let port: UInt16
    let token: String
    private let listener: NWListener
    private let handler: Handler

    init(port: UInt16, token: String, handler: @escaping Handler) throws {
        self.port = port
        self.token = token
        self.handler = handler
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
    }

    /// The address to open on the phone. Uses the Mac's Bonjour name so a home-screen bookmark keeps
    /// working when the Wi-Fi hands out a different IP address.
    var url: String {
        let host = (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" } ?? localIPAddress() ?? "localhost"
        return "http://\(host):\(port)/?k=\(token)"
    }

    var ipURL: String? { localIPAddress().map { "http://\($0):\(port)/?k=\(token)" } }

    func start(onFailure: @escaping (Error) -> Void) {
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { onFailure(error) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            self?.receive(on: connection, buffer: Data())
        }
        listener.start(queue: .main)
    }

    func stop() { listener.cancel() }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            let buffer = buffer + (data ?? Data())
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                self.respond(to: head, on: connection)
            } else if isComplete || error != nil || buffer.count > 16_384 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        // Request line: "GET /api/state?k=abc HTTP/1.1"
        let parts = head.split(separator: "\r\n", maxSplits: 1).first?.split(separator: " ") ?? []
        var response = Response(status: 400, contentType: "text/plain", body: Data("Bad request".utf8))
        if parts.count >= 2, let components = URLComponents(string: "http://remote" + parts[1]) {
            let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
            if query["k"] == token {
                response = handler(components.path, query)
            } else {
                response = Response(status: 403, contentType: "text/plain; charset=utf-8",
                                    body: Data("Scan the QR code shown in Terminal to open the remote.".utf8))
            }
        }

        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found"][response.status] ?? "OK"
        var header = "HTTP/1.1 \(response.status) \(reason)\r\n"
        header += "Content-Type: \(response.contentType)\r\n"
        header += "Content-Length: \(response.body.count)\r\n"
        header += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + response.body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// The access code for the remote, kept between runs so a home-screen bookmark keeps working.
func remoteToken() -> String {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let folder = support.appendingPathComponent("MacDialogBoost", isDirectory: true)
    let file = folder.appendingPathComponent("remote-token")

    // Carry over the code from when this was called Commentary Boost.
    let oldFolder = support.appendingPathComponent("CommentaryBoost", isDirectory: true)
    if !FileManager.default.fileExists(atPath: folder.path), FileManager.default.fileExists(atPath: oldFolder.path) {
        try? FileManager.default.moveItem(at: oldFolder, to: folder)
    }
    if let saved = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty {
        return saved
    }
    let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
    let token = String((0..<10).map { _ in alphabet.randomElement()! })
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? token.write(to: file, atomically: true, encoding: .utf8)
    return token
}

/// The Mac's IPv4 address on Wi-Fi/Ethernet, as a fallback for when `.local` names don't resolve.
private func localIPAddress() -> String? {
    var addresses: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
    defer { freeifaddrs(addresses) }
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let interface = pointer.pointee
        let name = String(cString: interface.ifa_name)
        guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), name.hasPrefix("en") else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            return String(cString: host)
        }
    }
    return nil
}
