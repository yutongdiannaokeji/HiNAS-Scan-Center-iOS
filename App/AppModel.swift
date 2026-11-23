import Foundation
import SwiftUI

@MainActor final class AppModel: ObservableObject {
    @Published var host = UserDefaults.standard.string(forKey: "host") ?? "192.168.31.47"
    @Published var port = UserDefaults.standard.integer(forKey: "port") == 0 ? 8088 : UserDefaults.standard.integer(forKey: "port")
    @Published var user = UserDefaults.standard.string(forKey: "user") ?? "actart"
    @Published var password = ""
    @Published var capabilities: ScanCapabilities?
    @Published var connected = false
    @Published var busy = false
    @Published var status = "连接家中的 HiNAS，开始扫描。"
    @Published var error: String?
    @Published var progress: Double?
    @Published var pending: PendingScan?
    @Published var exportURL: URL?
    @Published var tab = 0
    @Published var printCaps: PrintCapabilities?
    @Published var printFile: URL?
    @Published var printName = ""
    @Published var printOptions = PrintOptions()
    @Published var printReceipt: PendingPrint?
    @Published var printStatus = "选择 PDF、照片或文字。"
    @Published var printProgress: Double?
    @Published var printing = false
    @Published var libraryError: String?
    let library: DocumentLibrary
    private(set) var client: HiNASClient?
    private var scanTask: Task<Void, Never>?
    private var printTask: Task<Void, Never>?

    init(library: DocumentLibrary) {
        self.library = library
        if let data = UserDefaults.standard.data(forKey: "pendingScan") { pending = try? JSONDecoder().decode(PendingScan.self, from: data) }
        if let data = UserDefaults.standard.data(forKey: "pendingPrint") { printReceipt = try? JSONDecoder().decode(PendingPrint.self, from: data) }
        if pending != nil { status = "上次扫描尚未接收完，连接同一盒子后继续接收。" }
        if printReceipt != nil { printStatus = "上次打印已有提交记录，请先查询回执。" }
    }

    func connect() async {
        guard !busy else { return }
        busy = true
        defer { busy = false; password = "" }
        do {
            let address = try ServerAddress(host: host, port: port)
            let target = HiNASClient(address: address)
            let capabilities = try await target.login(user: user, password: password)
            client = target; self.capabilities = capabilities; connected = true
            UserDefaults.standard.set(address.host, forKey: "host")
            UserDefaults.standard.set(address.port, forKey: "port")
            UserDefaults.standard.set(user, forKey: "user")
            status = "Brother 已连接"
            if let pending, pending.server != address { status = "已连接。上次扫描属于另一台盒子。" }
        } catch { connected = false; self.error = readable(error) }
    }

    func start(source: ScanSource, dpi: Int) {
        guard let client, let capabilities, !busy, pending == nil else { return }
        guard capabilities.resolutions(for: source).contains(dpi), source != .feeder || capabilities.supportsFeeder else {
            error = "所选来源或分辨率尚未由盒子提供。"; return
        }
        do {
            let doc = try library.create()
            var options = ScanOptions(); options.source = source; options.dpi = dpi; options.limit = source == .feeder ? 10 : 1
            pending = PendingScan(server: client.address, documentID: doc, options: options)
            try savePending()
            busy = true; status = "正在启动\(source.title)…"
            scanTask = Task {
                defer { busy = false; progress = nil }
                do {
                    let job = try await client.start(options)
                    pending?.jobID = job
                    try savePending()
                    try await receive()
                } catch {
                    if pending?.jobID == nil { status = "启动回执未确认，请先检查盒子任务，避免重复进稿。" }
                    else { status = "接收中断。已下载的页面保存在文档中。" }
                    self.error = readable(error)
                }
            }
        } catch { self.error = readable(error) }
    }

    func resume() {
        guard !busy else { return }
        busy = true
        scanTask = Task {
            defer { busy = false; progress = nil }
            do { try await receive() } catch { self.error = readable(error); status = "接收中断，可继续接收同一任务。" }
        }
    }

    private func receive() async throws {
        guard let client, let state = pending, let jobID = state.jobID, client.address == state.server else {
            throw ServiceError("请连接原盒子。若未收到启动回执，请先在管理页检查在途扫描。")
        }
        let deadline = Date().addingTimeInterval(1200)
        while Date() < deadline {
            try Task.checkCancellation()
            let overview = try await client.overview()
            guard let job = overview.jobs.first(where: { $0.id == jobID }) else { throw ServiceError("盒子已找不到这项扫描。已下载的页面仍在文档中，请检查原稿后结束此次接收。") }
            var pages = job.pages ?? []
            if job.status == "complete" && state.options.source == .flatbed && pages.isEmpty {
                pages = [ScanPageReply(file: "original.png", dpi: job.result?.dpi ?? Double(state.options.dpi), width: nil, height: nil)]
            }
            guard pages.count <= 10 else { throw ServiceError("服务器返回的批次超出页数上限。") }
            for page in pages where pending?.files.contains(page.file) == false {
                guard HiNASClient.validPage(page.file) else { throw ServiceError("扫描页面编号无效。") }
                let name = jobID + "-" + page.file
                let target = library.folder(state.documentID).appendingPathComponent(name)
                status = "正在接收第 \((pending?.files.count ?? 0) + 1) 页原图"
                if !FileManager.default.fileExists(atPath: target.path) {
                    try await client.download(job: jobID, file: page.file, to: target) { fraction in
                        Task { @MainActor in self.progress = fraction }
                    }
                }
                let info = try PNGInfo.read(target)
                guard page.dpi == Double(state.options.dpi) else { throw ServiceError("原图 DPI 与所选档位不一致。") }
                try library.append(DocumentPage(id: UUID(), file: name, dpi: Int(page.dpi), width: info.width, height: info.height), document: state.documentID)
                pending?.files.append(page.file)
                try savePending()
                progress = nil
            }
            if job.status == "complete" {
                let total = pending?.files.count ?? 0
                guard total > 0 else { throw ServiceError("本次扫描没有返回页面。") }
                pending = nil; try savePending(); status = "已接收 \(total) 页 · \(state.options.dpi) dpi"; tab = 1
                return
            }
            if ["failed", "canceled"].contains(job.status) {
                pending = nil; try savePending()
                throw ServiceError(job.error ?? job.result?.error ?? "扫描已停止，已接收的页面保存在文档中。")
            }
            status = "正在扫描 · 已接收 \(pending?.files.count ?? 0) 页"
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw ServiceError("等待超时。可重新连接后继续接收，或停止盒子的在途扫描。")
    }

    func cancel() async {
        guard let client, let pending, let id = pending.jobID, pending.server == client.address else { return }
        do {
            try await client.cancel(id)
            scanTask?.cancel()
            self.pending = nil; try savePending(); status = "已请求停止，已接收的页面保存在文档中。"
        } catch { self.error = readable(error) }
    }

    func clearPendingAfterCheck() {
        guard !busy else { return }
        pending = nil
        do { try savePending() } catch { self.error = readable(error) }
    }

    private func savePending() throws {
        if let pending { UserDefaults.standard.set(try JSONEncoder().encode(pending), forKey: "pendingScan") }
        else { UserDefaults.standard.removeObject(forKey: "pendingScan") }
    }

    func export(_ id: UUID) async throws -> URL {
        guard let document = library.document(id), !document.pages.isEmpty else { throw ServiceError("文档还没有页面。") }
        let entries = document.pages.map { (library.pageURL($0, document: id), $0) }
        let out = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let target = out.appendingPathComponent(UUID().uuidString + ".pdf")
        return try await Task.detached(priority: .userInitiated) {
            try LosslessPDF.write(pages: entries, to: target)
            return target
        }.value
    }

    func loadPrintCapabilities() async {
        do {
            let target: HiNASClient
            if let client { target = client }
            else { target = HiNASClient(address: try ServerAddress(host: host, port: port)); client = target }
            printCaps = try await target.printCapabilities()
            if let papers = printCaps?.papers, !papers.contains(where: { $0.value == printOptions.media }), let first = papers.first { printOptions.media = first.value }
        } catch { self.error = readable(error) }
    }

    func submitPrint() {
        guard !printing, printReceipt == nil, let file = printFile, let client, printCaps?.ready == true else { return }
        let mime = file.pathExtension.lowercased() == "pdf" ? "application/pdf" : "text/plain"
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        printReceipt = PendingPrint(requestID: id, server: client.address)
        persistPrint()
        printing = true
        printStatus = "正在发送文件"
        printTask = Task {
            defer { printing = false; printProgress = nil }
            do {
                let reply = try await client.upload(file: file, mime: mime, options: printOptions, requestID: id) { fraction in
                    Task { @MainActor in self.printProgress = fraction }
                }
                printReceipt?.jobID = reply.job_id; persistPrint()
                printStatus = "CUPS 已接收任务 #\(reply.job_id)"
                await checkPrintReceipt()
            } catch { printStatus = "发送结果待确认，请查询回执。"; self.error = readable(error) }
        }
    }

    func checkPrintReceipt() async {
        guard let receipt = printReceipt, let client, receipt.server == client.address else { return }
        do {
            if printCaps == nil { _ = try await client.printCapabilities() }
            let result = try await client.receipt(receipt.requestID)
            printReceipt?.jobID = result.job_id; persistPrint()
            let states = [3: "等待打印", 4: "任务已暂停", 5: "正在处理打印", 6: "任务已停止", 7: "任务已取消", 8: "打印失败", 9: "CUPS 报告任务已完成"]
            printStatus = states[result.job_state ?? 0] ?? (result.status == "not-submitted" ? "盒子没有这项提交记录。" : "提交记录为 \(result.status)，请检查盒子队列。")
        } catch { self.error = readable(error) }
    }

    func finishPrintReceipt() { printReceipt = nil; persistPrint(); printStatus = "可以选择下一份文件。" }
    private func persistPrint() {
        if let printReceipt, let data = try? JSONEncoder().encode(printReceipt) { UserDefaults.standard.set(data, forKey: "pendingPrint") }
        else { UserDefaults.standard.removeObject(forKey: "pendingPrint") }
    }

    func readable(_ error: Error) -> String {
        if let service = error as? ServiceError { return service.message }
        if let url = error as? URLError, url.code == .notConnectedToInternet || url.code == .cannotConnectToHost || url.code == .timedOut {
            return "无法连接盒子。请检查家庭 Wi-Fi、局域网访问权限和设备地址。"
        }
        return error.localizedDescription
    }
}
