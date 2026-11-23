import Foundation

struct ServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct ServerAddress: Equatable, Codable {
    let host: String
    let port: Int

    init(host: String, port: Int) throws {
        let parts = host.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { throw ServiceError("请输入盒子的局域网 IPv4 地址。") }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4, zip(parts, octets).allSatisfy({ String($0.1) == String($0.0) }),
              (octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 192 && octets[1] == 168)),
              (1...65535).contains(port) else { throw ServiceError("请输入可信局域网地址和有效端口。") }
        self.host = octets.map(String.init).joined(separator: ".")
        self.port = port
    }

    var origin: String { "http://\(host):\(port)" }
    func url(_ path: String) throws -> URL {
        guard path.hasPrefix("/api/"), !path.contains(".."), !path.contains("?"), !path.contains("#"),
              let url = URL(string: origin + path), url.host == host, url.port == port else {
            throw ServiceError("服务返回了无效的文件地址。")
        }
        return url
    }
}

struct SessionReply: Decodable { let authenticated: Bool; let csrf: String }
struct ProbeReply: Decodable { let capabilities: ScanCapabilities }
struct ScanCapabilities: Decodable {
    struct Device: Decodable { let model: String? }
    struct Options: Decodable {
        struct Numbers: Decodable { let values: [Double]? }
        struct Strings: Decodable { let values: [String]? }
        let resolution: Numbers?
        let source: Strings?
    }
    struct API: Decodable { let adf_batch: Bool?; let adf_max_dpi: Int?; let adf_page_limit: Int? }
    let ok: Bool
    let error: String?
    let device: Device?
    let options: Options?
    let scan_center_api: API?
    var supportsFeeder: Bool { scan_center_api?.adf_batch == true && options?.source?.values?.contains("Automatic Document Feeder") == true }
    var resolutions: [Int] { [100, 150, 200, 300, 400, 600].filter { options?.resolution?.values?.contains(Double($0)) == true } }
    func resolutions(for source: ScanSource) -> [Int] {
        resolutions.filter { $0 <= (source == .feeder ? (scan_center_api?.adf_max_dpi ?? 0) : 600) }
    }
}

enum ScanSource: String, Codable, CaseIterable, Identifiable {
    case feeder = "Automatic Document Feeder"
    case flatbed = "FlatBed"
    var id: String { rawValue }
    var title: String { self == .feeder ? "自动进稿器" : "玻璃平板" }
    var icon: String { self == .feeder ? "tray.and.arrow.down" : "scanner" }
}

struct ScanOptions: Codable {
    enum CodingKeys: String, CodingKey { case source, dpi, limit, mode, x, y, width, height, preview }
    var source = ScanSource.feeder
    var dpi = 600
    var limit = 10
    let mode = "24bit Color"
    let x: Double = 0
    let y: Double = 0
    let width: Double = 210
    let height: Double = 297
    let preview = false
}

struct ScanPageReply: Decodable { let file: String; let dpi: Double; let width: Int?; let height: Int? }
struct ScanJob: Decodable, Identifiable {
    struct Result: Decodable { let ok: Bool?; let error: String?; let dpi: Double?; let pages: Int? }
    let id: String
    let status: String
    let pages: [ScanPageReply]?
    let result: Result?
    let error: String?
}
struct ScanOverview: Decodable { let active: String?; let jobs: [ScanJob] }
struct StartReply: Decodable { let id: String }
struct EmptyReply: Decodable {}

struct PendingScan: Codable {
    var jobID: String?
    let server: ServerAddress
    let documentID: UUID
    let options: ScanOptions
    var files: [String] = []
}

struct DocumentPage: Identifiable, Codable, Equatable {
    let id: UUID
    let file: String
    let dpi: Int
    let width: Int
    let height: Int
    var rotation = 0
}
struct ScanDocument: Identifiable, Codable {
    let id: UUID
    var title: String
    let created: Date
    var pages: [DocumentPage]
}

struct PrintCapabilities: Decodable {
    struct Paper: Decodable, Identifiable { let value: String; let label: String; var id: String { value } }
    let ready: Bool
    let message: String
    let papers: [Paper]
    let hq: Bool
    let formats: [String]
}
struct GuestSession: Decodable { let csrf: String }
struct PrintReply: Decodable { let job_id: Int; let message: String }
struct PrintReceipt: Decodable { let status: String; let job_id: Int?; let job_state: Int? }
struct PrintOptions: Codable, Equatable {
    var copies = 1
    var pages = ""
    var orientation = "portrait"
    var scale = "fit"
    var media = "iso_a4_210x297mm"
    var quality = "standard"
}
struct PendingPrint: Codable {
    let requestID: String
    let server: ServerAddress
    var jobID: Int?
}
