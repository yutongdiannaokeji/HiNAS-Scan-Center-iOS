import Foundation
import ImageIO

struct PNGInfo {
    let width: Int
    let height: Int
    let colors: Int
    let chunks: [(offset: UInt64, size: Int)]
    var compressedSize: Int { chunks.reduce(0) { $0 + $1.size } }

    static func read(_ url: URL) throws -> PNGInfo {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.read(upToCount: 8) == Data([137, 80, 78, 71, 13, 10, 26, 10]) else { throw ServiceError("扫描原图不是 PNG。") }
        var width = 0, height = 0, colors = 0
        var chunks: [(UInt64, Int)] = []
        let fileSize = try file.seekToEnd()
        try file.seek(toOffset: 8)
        var finished = false
        while try file.offset() + 12 <= fileSize {
            guard let header = try file.read(upToCount: 8), header.count == 8 else { break }
            let size = Int(header.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            let kind = String(data: header.suffix(4), encoding: .ascii)
            let offset = try file.offset()
            guard size <= 120 * 1024 * 1024, offset + UInt64(size) + 4 <= fileSize else { throw ServiceError("PNG 数据不完整。") }
            if kind == "IHDR" {
                guard width == 0, size == 13, let data = try file.read(upToCount: 13), data.count == 13 else { throw ServiceError("PNG 图像头无效。") }
                width = Int(data.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
                height = Int(data.dropFirst(4).prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
                guard width > 0, height > 0, width <= 12000, height <= 12000, width * height <= 36_100_000,
                      data[8] == 8, [0, 2].contains(data[9]), data[10] == 0, data[11] == 0, data[12] == 0 else {
                    throw ServiceError("扫描原图的像素或色彩格式不受支持。")
                }
                colors = data[9] == 2 ? 3 : 1
            } else if kind == "IDAT" {
                chunks.append((offset, size))
            } else if kind == "IEND" {
                finished = true
                break
            }
            try file.seek(toOffset: offset + UInt64(size) + 4)
        }
        guard finished, width > 0, !chunks.isEmpty else { throw ServiceError("扫描原图缺少完整图像数据。") }
        return PNGInfo(width: width, height: height, colors: colors, chunks: chunks)
    }
}

enum LosslessPDF {
    /// Embed the scanner's existing PNG Deflate stream, preserving every source pixel.
    static func write(pages: [(URL, DocumentPage)], to destination: URL) throws {
        guard !pages.isEmpty else { throw ServiceError("先扫描至少一页。") }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".part")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close(); try? FileManager.default.removeItem(at: temporary) }
        var offsets: [UInt64] = [0]
        func text(_ value: String) throws { try output.write(contentsOf: Data(value.utf8)) }
        func object(_ number: Int, _ content: String) throws {
            guard offsets.count == number else { throw ServiceError("PDF 对象顺序异常。") }
            offsets.append(try output.offset())
            try text("\(number) 0 obj\n\(content)\nendobj\n")
        }
        try text("%PDF-1.4\n%ScanCenter\n")
        try object(1, "<< /Type /Catalog /Pages 2 0 R >>")
        let kids = pages.indices.map { "\(3 + $0 * 3) 0 R" }.joined(separator: " ")
        try object(2, "<< /Type /Pages /Count \(pages.count) /Kids [\(kids)] >>")
        for (index, entry) in pages.enumerated() {
            try Task.checkCancellation()
            let (url, page) = entry
            let info = try PNGInfo.read(url)
            guard (100...600).contains(page.dpi), page.width == info.width, page.height == info.height else { throw ServiceError("扫描原图尺寸与文档记录不一致。") }
            let w = Double(info.width) * 72 / Double(page.dpi)
            let h = Double(info.height) * 72 / Double(page.dpi)
            let rotated = page.rotation % 180 != 0
            let pageNumber = 3 + index * 3
            try object(pageNumber, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(rotated ? h : w) \(rotated ? w : h)] /Resources << /XObject << /Image \(pageNumber + 1) 0 R >> >> /Contents \(pageNumber + 2) 0 R >>")
            offsets.append(try output.offset())
            let color = info.colors == 3 ? "/DeviceRGB" : "/DeviceGray"
            try text("\(pageNumber + 1) 0 obj\n<< /Type /XObject /Subtype /Image /Width \(info.width) /Height \(info.height) /ColorSpace \(color) /BitsPerComponent 8 /Interpolate false /Filter /FlateDecode /DecodeParms << /Predictor 15 /Colors \(info.colors) /BitsPerComponent 8 /Columns \(info.width) >> /Length \(info.compressedSize) >>\nstream\n")
            let source = try FileHandle(forReadingFrom: url)
            do {
                for chunk in info.chunks {
                    try source.seek(toOffset: chunk.offset)
                    var remaining = chunk.size
                    while remaining > 0 {
                        guard let data = try source.read(upToCount: min(remaining, 65536)), !data.isEmpty else { throw ServiceError("读取扫描原图失败。") }
                        try output.write(contentsOf: data)
                        remaining -= data.count
                    }
                }
                try source.close()
            } catch { try? source.close(); throw error }
            try text("\nendstream\nendobj\n")
            let matrix: String
            switch page.rotation % 360 {
            case 90: matrix = "0 \(w) -\(h) 0 \(h) 0"
            case 180: matrix = "-\(w) 0 0 -\(h) \(w) \(h)"
            case 270: matrix = "0 -\(w) \(h) 0 0 \(w)"
            default: matrix = "\(w) 0 0 \(h) 0 0"
            }
            let content = "q\n\(matrix) cm\n/Image Do\nQ\n"
            try object(pageNumber + 2, "<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream")
        }
        let xref = try output.offset()
        try text("xref\n0 \(offsets.count)\n0000000000 65535 f \n")
        for offset in offsets.dropFirst() { try text(String(format: "%010llu 00000 n \n", offset)) }
        try text("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n")
        try output.synchronize()
        try output.close()
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}

enum Thumbnails {
    static func image(_ url: URL, maxPixels: Int = 1200) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                      kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
