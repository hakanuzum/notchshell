import Foundation
import Network
import AppKit
import MCP

/// Embeds an MCP HTTP server inside the running GUI app.
/// Listens on localhost:PORT, bridges HTTP to the MCP SDK's StatelessHTTPServerTransport.
/// Tool calls are routed directly to ControlServer.handleRequest (no socket hop).
@MainActor
final class MCPHTTPServer {
    private let port: UInt16
    private var listener: NWListener?
    private var mcpServer: Server?
    private var transport: StatelessHTTPServerTransport?
    private weak var controlServer: ControlServer?
    private var wakeObserver: Any?
    private var restartAttempts = 0
    private static let maxRestartAttempts = 5

    nonisolated static let defaultPort: UInt16 = 19876

    init(controlServer: ControlServer, port: UInt16 = MCPHTTPServer.defaultPort) {
        self.controlServer = controlServer
        self.port = port
    }

    func start() {
        let transport = StatelessHTTPServerTransport()
        self.transport = transport

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let server = Server(
            name: "hakuke",
            version: version,
            capabilities: .init(tools: .init(listChanged: false))
        )
        self.mcpServer = server

        Task {
            await server.withMethodHandler(ListTools.self) { _ in
                ListTools.Result(tools: Self.allTools)
            }

            await server.withMethodHandler(CallTool.self) { [weak self] params in
                guard let self else {
                    return CallTool.Result(content: [.text("{\"ok\":false,\"error\":\"server gone\"}")], isError: true)
                }
                return try await MainActor.run {
                    try self.handleToolCall(params)
                }
            }

            do {
                try await server.start(transport: transport)
            } catch {
                print("MCPHTTPServer: failed to start MCP server: \(error)")
            }
        }

        startListener()

        // Restart listener after system wake from sleep
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("MCPHTTPServer: system wake — restarting listener")
            self?.restartAttempts = 0
            self?.restartListener()
        }
    }

    func stop() {
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
        listener?.cancel()
        listener = nil
        Task {
            await transport?.disconnect()
        }
    }

    private func restartListener() {
        guard restartAttempts < Self.maxRestartAttempts else {
            print("MCPHTTPServer: max restart attempts (\(Self.maxRestartAttempts)) reached — giving up")
            return
        }
        restartAttempts += 1
        listener?.cancel()
        listener = nil
        // Delay to let the port release
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startListener()
        }
    }

    // MARK: - HTTP listener (Network.framework)

    private func startListener() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("MCPHTTPServer: failed to create listener: \(error)")
            return
        }

        let capturedPort = port
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async { self?.restartAttempts = 0 }
                print("MCPHTTPServer: listening on http://localhost:\(capturedPort)/mcp")
            case .failed(let error):
                print("MCPHTTPServer: listener failed: \(error) — restarting")
                DispatchQueue.main.async {
                    self?.restartListener()
                }
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            // Reject non-loopback connections for security
            if let remote = connection.currentPath?.remoteEndpoint,
               case .hostPort(let host, _) = remote {
                let hostStr = "\(host)"
                if hostStr != "127.0.0.1" && hostStr != "::1" && hostStr != "localhost" {
                    print("MCPHTTPServer: rejected non-localhost connection from \(hostStr)")
                    connection.cancel()
                    return
                }
            }
            connection.start(queue: .global())
            MCPHTTPServer.receiveHTTP(connection, server: self)
        }

        listener?.start(queue: .main)
    }

    // MARK: - HTTP request handling (nonisolated static to avoid actor isolation in NW callbacks)

    /// Maximum request size to prevent abuse (1 MB).
    private static let maxRequestSize = 1_048_576

    private nonisolated static func receiveHTTP(_ connection: NWConnection, server: MCPHTTPServer?, accumulated: Data = Data()) {
        let remaining = maxRequestSize - accumulated.count
        guard remaining > 0 else {
            let resp = "HTTP/1.1 413 Payload Too Large\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(65536, remaining)) { data, _, isComplete, error in
            guard let data, !data.isEmpty else {
                connection.cancel()
                return
            }

            let buffer = accumulated + data

            guard let parsed = parseHTTPRequest(buffer) else {
                if isComplete {
                    // Connection closed without valid HTTP
                    print("MCPHTTPServer: failed to parse HTTP request (\(buffer.count) bytes)")
                    let resp = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    connection.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
                } else {
                    // Incomplete data — read more
                    receiveHTTP(connection, server: server, accumulated: buffer)
                }
                return
            }

            // Check if body is complete per Content-Length
            if let clStr = parsed.headers.first(where: { $0.key.lowercased() == "content-length" })?.value,
               let cl = Int(clStr),
               let body = parsed.body, body.count < cl {
                // Need more body data
                receiveHTTP(connection, server: server, accumulated: buffer)
                return
            }

            #if DEBUG
            print("MCPHTTPServer: \(parsed.method) \(parsed.path)")
            for (key, value) in parsed.headers {
                print("MCPHTTPServer:   \(key): \(value)")
            }
            if let body = parsed.body, let bodyStr = String(data: body, encoding: .utf8) {
                let preview = bodyStr.prefix(200)
                print("MCPHTTPServer:   body: \(preview)\(bodyStr.count > 200 ? "..." : "")")
            }
            #endif

            if parsed.path != "/mcp" {
                let body = "{\"error\":\"Not Found\"}"
                let resp = "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            let httpRequest = HTTPRequest(
                method: parsed.method,
                headers: parsed.headers,
                body: parsed.body
            )

            Task { @MainActor in
                guard let transport = server?.transport else {
                    connection.cancel()
                    return
                }
                let response = await transport.handleRequest(httpRequest)
                #if DEBUG
                print("MCPHTTPServer: response \(response.statusCode)")
                if let body = response.bodyData, let str = String(data: body, encoding: .utf8) {
                    let preview = str.prefix(200)
                    print("MCPHTTPServer:   body: \(preview)\(str.count > 200 ? "..." : "")")
                }
                #endif
                sendHTTPResponse(response, on: connection)
            }
        }
    }

    // MARK: - Minimal HTTP parser (nonisolated)

    private struct ParsedHTTP: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data?
    }

    private nonisolated static func parseHTTPRequest(_ data: Data) -> ParsedHTTP? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }

        let parts = raw.components(separatedBy: "\r\n\r\n")
        guard !parts.isEmpty else { return nil }

        let headerSection = parts[0]
        let bodyString = parts.count > 1 ? parts[1...].joined(separator: "\r\n\r\n") : nil

        let lines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let tokens = requestLine.split(separator: " ", maxSplits: 2)
        guard tokens.count >= 2 else { return nil }

        let method = String(tokens[0])
        let fullPath = String(tokens[1])
        let path = fullPath.split(separator: "?").first.map(String.init) ?? fullPath

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        var body: Data? = nil
        if let bodyString, !bodyString.isEmpty {
            body = bodyString.data(using: .utf8)
        }

        return ParsedHTTP(method: method, path: path, headers: headers, body: body)
    }

    // MARK: - HTTP response writer (nonisolated)

    private nonisolated static func sendHTTPResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let statusLine: String
        switch response.statusCode {
        case 200: statusLine = "HTTP/1.1 200 OK"
        case 202: statusLine = "HTTP/1.1 202 Accepted"
        case 400: statusLine = "HTTP/1.1 400 Bad Request"
        case 404: statusLine = "HTTP/1.1 404 Not Found"
        case 405: statusLine = "HTTP/1.1 405 Method Not Allowed"
        case 500: statusLine = "HTTP/1.1 500 Internal Server Error"
        default:  statusLine = "HTTP/1.1 \(response.statusCode) Error"
        }

        let bodyData = response.bodyData
        var responseHeaders = response.headers
        responseHeaders["Connection"] = "close"
        if let bodyData {
            responseHeaders["Content-Length"] = "\(bodyData.count)"
        } else {
            responseHeaders["Content-Length"] = "0"
        }

        var headerString = statusLine + "\r\n"
        for (key, value) in responseHeaders {
            headerString += "\(key): \(value)\r\n"
        }
        headerString += "\r\n"

        var responseData = headerString.data(using: .utf8) ?? Data()
        if let bodyData {
            responseData.append(bodyData)
        }

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Tool definitions

    nonisolated static let allTools: [Tool] = [
        Tool(name: "state", description: "Get terminal state (visible, pinned, tab count, active session)",
             inputSchema: .object(["type": .string("object"), "properties": .object([:])]) ),
        Tool(name: "list", description: "List tabs and sessions (panes). Each session has an 8-char session_id.",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "include_panes": .object(["type": .string("boolean"), "description": .string("Include pane tree structure (default: false)")])
                ])
             ])),
        Tool(name: "toggle", description: "Toggle terminal visibility (show/hide)",
             inputSchema: .object(["type": .string("object"), "properties": .object([:])]) ),
        Tool(name: "show", description: "Show the terminal",
             inputSchema: .object(["type": .string("object"), "properties": .object([:])]) ),
        Tool(name: "hide", description: "Hide the terminal",
             inputSchema: .object(["type": .string("object"), "properties": .object([:])]) ),
        Tool(name: "pin", description: "Pin the terminal (stay visible when focus is lost)",
             inputSchema: .object(["type": .string("object"), "properties": .object([:])]) ),
        Tool(name: "unpin", description: "Unpin the terminal (auto-hide on focus loss)",
             inputSchema: .object(["type": .string("object"), "properties": .object([:])]) ),
        Tool(name: "new_tab", description: "Create a new terminal tab. Returns session_id of the new session.",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "directory": .object(["type": .string("string"), "description": .string("Working directory for the new tab")]),
                    "name": .object(["type": .string("string"), "description": .string("Tab title (overrides auto-detected title)")])
                ])
             ])),
        Tool(name: "focus", description: "Focus a session (auto-switches tab), a tab (by tab_id/index), or navigate panes (direction: next/prev)",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "session_id": .object(["type": .string("string"), "description": .string("Session (pane) ID — auto-switches to its tab")]),
                    "tab_id": .object(["type": .string("string"), "description": .string("Tab container ID")]),
                    "index": .object(["type": .string("integer"), "description": .string("Tab index (0-based)")]),
                    "direction": .object(["type": .string("string"), "description": .string("Pane navigation: next or prev")])
                ])
             ])),
        Tool(name: "close_session", description: "Close a session (pane) or a tab. If last pane, tab closes too.",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "session_id": .object(["type": .string("string"), "description": .string("Session (pane) ID to close")]),
                    "tab_id": .object(["type": .string("string"), "description": .string("Tab ID to close (all panes)")])
                ])
             ])),
        Tool(name: "execute", description: "Execute a shell command in a session. Sends text and presses Enter.",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "command": .object(["type": .string("string"), "description": .string("Shell command to execute")]),
                    "session_id": .object(["type": .string("string"), "description": .string("Target session (default: focused)")])
                ]),
                "required": .array([.string("command")])
             ])),
        Tool(name: "read", description: "Read terminal output from a session (last N lines)",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "session_id": .object(["type": .string("string"), "description": .string("Target session (default: focused)")]),
                    "lines": .object(["type": .string("integer"), "description": .string("Number of lines to read (default: 20)")])
                ])
             ])),
        Tool(name: "paste", description: "Paste text into a session (no Enter key appended)",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string"), "description": .string("Text to paste")]),
                    "session_id": .object(["type": .string("string"), "description": .string("Target session (default: focused)")])
                ]),
                "required": .array([.string("text")])
             ])),
        Tool(name: "control_char", description: "Send a control character to a session (ctrl+c, ctrl+d, enter, esc, tab, etc.)",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "key": .object(["type": .string("string"), "description": .string("Key: c, d, z, a, e, k, l, u, w, enter, esc, tab")]),
                    "session_id": .object(["type": .string("string"), "description": .string("Target session (default: focused)")])
                ]),
                "required": .array([.string("key")])
             ])),
        Tool(name: "clear", description: "Clear a session screen (sends Ctrl+L)",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "session_id": .object(["type": .string("string"), "description": .string("Target session (default: focused)")])
                ])
             ])),
        Tool(name: "split", description: "Split a session horizontally or vertically. Returns new session_id.",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "direction": .object(["type": .string("string"), "description": .string("Split direction: h (horizontal) or v (vertical)")]),
                    "session_id": .object(["type": .string("string"), "description": .string("Session to split (default: focused)")]),
                    "ratio": .object(["type": .string("number"), "description": .string("Split ratio 0.1-0.9 for first pane (default: 0.5)")])
                ]),
                "required": .array([.string("direction")])
             ])),
        Tool(name: "resize_split", description: "Resize a split pane. Set absolute ratio, delta, or equalize all splits.",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "ratio": .object(["type": .string("number"), "description": .string("Absolute ratio 0.1-0.9 for parent split")]),
                    "delta": .object(["type": .string("number"), "description": .string("Resize by delta percentage points (e.g. 10 = grow 10%)")]),
                    "equalize": .object(["type": .string("boolean"), "description": .string("Set all splits to equal ratio")]),
                    "session_id": .object(["type": .string("string"), "description": .string("Target session (default: focused)")])
                ])
             ])),
        Tool(name: "set_appearance", description: "Set tab title (by tab_id, session_id, or active tab)",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "title": .object(["type": .string("string"), "description": .string("New tab title (empty to reset)")]),
                    "tab_id": .object(["type": .string("string"), "description": .string("Tab ID")]),
                    "session_id": .object(["type": .string("string"), "description": .string("Session ID (resolves to its tab)")])
                ]),
                "required": .array([.string("title")])
             ])),
    ]

    // MARK: - Access control

    @MainActor static var accessState: String {
        get { UserDefaults.standard.string(forKey: "mcpAccess") ?? "ask" }
        set { UserDefaults.standard.set(newValue, forKey: "mcpAccess") }
    }

    @MainActor
    private func checkAccess() throws {
        let state = Self.accessState
        if state == "enabled" { return }
        if state == "disabled" {
            throw MCPError.internalError("MCP access disabled")
        }
        // "ask" — show dialog
        let alert = NSAlert()
        alert.messageText = "Allow MCP Access?"
        alert.informativeText = "An MCP client is trying to control hakuke via HTTP. Allow this?"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            Self.accessState = "enabled"
        } else {
            Self.accessState = "disabled"
            throw MCPError.internalError("MCP access denied by user")
        }
    }

    // MARK: - Tool call handler (direct, no socket)

    private func handleToolCall(_ params: CallTool.Parameters) throws -> CallTool.Result {
        try checkAccess()

        guard let controlServer else {
            throw MCPError.internalError("ControlServer not available")
        }

        let actionMap: [String: String] = [
            "state": "state", "list": "list", "toggle": "toggle",
            "show": "show", "hide": "hide", "pin": "pin", "unpin": "unpin",
            "new_tab": "new-tab", "focus": "focus", "close_session": "close-session",
            "execute": "execute", "read": "read", "paste": "paste",
            "control_char": "control-char", "clear": "clear", "split": "split",
            "resize_split": "resize-split", "set_appearance": "set-appearance",
        ]

        guard let action = actionMap[params.name] else {
            throw MCPError.invalidParams("Unknown tool: \(params.name)")
        }

        // Map MCP argument names (snake_case) to ControlServer JSON keys.
        let keyMap: [String: String] = [
            "include_panes": "include-panes",
            "session_id": "session_id",
            "tab_id": "tab_id",
            "close_session": "close-session",
        ]

        var request: [String: Any] = ["action": action]
        if let args = params.arguments {
            for (key, value) in args {
                let apiKey = keyMap[key] ?? key
                switch value {
                case .string(let s): request[apiKey] = s
                case .int(let i):    request[apiKey] = i
                case .double(let d): request[apiKey] = d
                case .bool(let b):   request[apiKey] = b
                default: break
                }
            }
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw MCPError.internalError("Failed to serialize request")
        }

        let response = controlServer.handleRequest(jsonString)
        return CallTool.Result(content: [.text(response)])
    }
}
