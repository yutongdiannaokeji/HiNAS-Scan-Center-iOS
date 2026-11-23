import Foundation

private final class LocalSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class TransferProgress: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    let progress: (Double) -> Void
    init(_ progress: @escaping (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 { progress(Double(totalBytesSent) / Double(totalBytesExpectedToSend)) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class HiNASClient {
    let address: ServerAddress
    private let session: URLSession
    private var csrf = ""
    private var printCSRF = ""
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(address: ServerAddress) {
        self.address = address
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 180
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config, delegate: LocalSessionDelegate(), delegateQueue: nil)
    }

    private func request(_ path: String, body: Data? = nil) throws -> URLRequest {
        var request = URLRequest(url: try address.url(path))
        request.setValue(address.origin, forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(path.hasPrefix("/api/guest/") ? printCSRF : csrf, forHTTPHeaderField: "X-CSRF-Token")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func check(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { throw ServiceError("服务返回了无效响应。") }
        guard (200...299).contains(http.statusCode) else {
            if let data, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let message = value["error"] as? String {
                throw ServiceError(message)
            }
            if http.statusCode == 401 { throw ServiceError("会话已过期，请重新连接盒子。") }
            throw ServiceError("服务返回 HTTP \(http.statusCode)，请检查盒子地址与端口。")
        }
    }

    func get<T: Decodable>(_ path: String, as: T.Type = T.self) async throws -> T {
        let (data, response) = try await session.data(for: request(path))
        try check(response, data: data)
        guard data.count <= 524_288 else { throw ServiceError("状态响应过大。") }
        return try decoder.decode(T.self, from: data)
    }

    func post<T: Decodable, Body: Encodable>(_ path: String, _ body: Body, as: T.Type = T.self) async throws -> T {
        let (data, response) = try await session.data(for: request(path, body: encoder.encode(body)))
        try check(response, data: data)
        guard data.count <= 524_288 else { throw ServiceError("状态响应过大。") }
        return try decoder.decode(T.self, from: data)
    }

    func login(user: String, password: String) async throws -> ScanCapabilities {
        let _: SessionReply = try await get("/api/session")
        let _: EmptyReply = try await post("/api/login", ["user": user, "password": password])
        let state: SessionReply = try await get("/api/session")
        guard state.authenticated && !state.csrf.isEmpty else { throw ServiceError("无法建立登录会话。") }
        csrf = state.csrf
        let response: ProbeReply = try await post("/api/scanner/probe", [String: String]())
        guard response.capabilities.ok else { throw ServiceError(response.capabilities.error ?? "USB 扫描仪暂未就绪。") }
        return response.capabilities
    }

    func start(_ options: ScanOptions) async throws -> String {
        let result: StartReply = try await post("/api/scanner/start", options)
        guard Self.validJob(result.id) else { throw ServiceError("启动回执缺少有效任务编号，请先查看盒子的在途任务。") }
        return result.id
    }
    func overview() async throws -> ScanOverview { try await get("/api/scanner") }
    func cancel(_ id: String) async throws {
        guard Self.validJob(id) else { throw ServiceError("任务编号无效。") }
        let _: EmptyReply = try await post("/api/scanner/cancel", ["id": id])
    }

    func download(job: String, file: String, to target: URL, progress: @escaping (Double) -> Void) async throws {
        guard Self.validJob(job), Self.validPage(file) else { throw ServiceError("原图地址无效。") }
        var request = try request("/api/scans/\(job)/\(file)")
        request.setValue("image/png", forHTTPHeaderField: "Accept")
        let (temporary, response) = try await session.download(for: request, delegate: TransferProgress(progress))
        defer { try? FileManager.default.removeItem(at: temporary) }
        try check(response)
        guard response.mimeType == "image/png", response.expectedContentLength <= 120 * 1024 * 1024 else {
            throw ServiceError("返回的扫描文件格式或大小不正确。")
        }
        let size = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size <= 120 * 1024 * 1024,
              response.expectedContentLength < 0 || size == response.expectedContentLength else { throw ServiceError("原图尚未完整下载，请继续接收。") }
        _ = try PNGInfo.read(temporary)
        try FileManager.default.moveItem(at: temporary, to: target)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
    }

    func printCapabilities() async throws -> PrintCapabilities {
        let state: GuestSession = try await post("/api/guest/session", [String: String]())
        printCSRF = state.csrf
        return try await get("/api/guest/capabilities")
    }

    func upload(file: URL, mime: String, options: PrintOptions, requestID: String,
                progress: @escaping (Double) -> Void) async throws -> PrintReply {
        var request = try request("/api/guest/print")
        request.httpMethod = "POST"
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue(String(decoding: try encoder.encode(options), as: UTF8.self), forHTTPHeaderField: "X-Print-Options")
        request.setValue(requestID, forHTTPHeaderField: "X-Print-Request")
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 && size <= 16 * 1024 * 1024 else { throw ServiceError("盒子打印入口最多接收 16 MiB。较大的 PDF 请用 AirPrint。") }
        let (data, response) = try await session.upload(for: request, fromFile: file, delegate: TransferProgress(progress))
        try check(response, data: data)
        return try decoder.decode(PrintReply.self, from: data)
    }

    func receipt(_ requestID: String) async throws -> PrintReceipt {
        try await post("/api/guest/receipt", ["request_id": requestID])
    }

    static func validJob(_ value: String) -> Bool { value.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil }
    static func validPage(_ value: String) -> Bool { value.range(of: "^(original|page-([1-9]|10))\\.png$", options: .regularExpression) != nil }
}
