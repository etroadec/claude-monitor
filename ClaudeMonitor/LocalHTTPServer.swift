import Foundation

class LocalHTTPServer {
    private var serverSocket: Int32 = -1
    private let queue = DispatchQueue(label: "com.edgard.claude-monitor.httpserver")
    private var _running = false
    private var running: Bool {
        get { queue.sync { _running } }
        set { queue.sync { _running = newValue } }
    }
    private var handler: ((String?, String?) -> Void)?

    func start(handler: @escaping (String?, String?) -> Void) -> UInt16? {
        self.handler = handler

        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return nil }

        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            close(serverSocket)
            return nil
        }

        guard listen(serverSocket, 1) == 0 else {
            close(serverSocket)
            return nil
        }

        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                getsockname(serverSocket, sockaddrPtr, &addrLen)
            }
        }
        let port = UInt16(bigEndian: boundAddr.sin_port)

        running = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptLoop()
        }

        return port
    }

    func stop() {
        running = false
        let sock = serverSocket
        serverSocket = -1
        if sock >= 0 { close(sock) }
    }

    private func acceptLoop() {
        while running {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(serverSocket, sockaddrPtr, &clientAddrLen)
                }
            }

            guard clientSocket >= 0, running else { break }

            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(clientSocket, &buffer, buffer.count)
            guard bytesRead > 0 else {
                close(clientSocket)
                continue
            }

            let requestString = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
            let (code, state) = parseCallback(from: requestString)

            let success = code != nil
            let html = """
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"><title>Claude Monitor</title></head>
            <body style="font-family:-apple-system,system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#1a1a2e;color:#e0e0e0">
            <div style="text-align:center">
            <h1 style="font-size:2em">\(success ? "&#x2713; Connect&eacute; !" : "&#x2717; Erreur")</h1>
            <p style="color:#888">\(success ? "Vous pouvez fermer cette fen&ecirc;tre." : "Aucun code re&ccedil;u. R&eacute;essayez.")</p>
            </div>
            </body>
            </html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            _ = response.withCString { ptr in
                write(clientSocket, ptr, strlen(ptr))
            }
            close(clientSocket)

            if code != nil {
                running = false
                DispatchQueue.main.async { [weak self] in
                    self?.handler?(code, state)
                }
                break
            }
        }
    }

    private func parseCallback(from request: String) -> (code: String?, state: String?) {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let pathPart = firstLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(pathPart)) else {
            return (nil, nil)
        }
        let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        return (code, state)
    }
}
