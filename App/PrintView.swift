import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

enum PrintPreparation {
    static func prepare(_ source: URL) throws -> URL {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let size = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size <= 120 * 1024 * 1024 else { throw ServiceError("选择的文件为空或超过 120 MiB。") }
        let ext = source.pathExtension.lowercased()
        if ["pdf", "txt"].contains(ext) {
            let destination = output.appendingPathExtension(ext)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16000, height <= 16000, width * height <= 36_100_000,
              let image = UIImage(contentsOfFile: source.path) else { throw ServiceError("请选 PDF、照片或 UTF-8 TXT，图片最多 3600 万像素。") }
        let destination = output.appendingPathExtension("pdf")
        let page = CGRect(x: 0, y: 0, width: 595.276, height: 841.89)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: destination) { context in
            context.beginPage()
            let inset = page.insetBy(dx: 23, dy: 23)
            let scale = min(inset.width / image.size.width, inset.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (page.width - size.width) / 2, y: (page.height - size.height) / 2, width: size.width, height: size.height))
        }
        return destination
    }

    @MainActor static func airPrint(_ url: URL) throws {
        guard UIPrintInteractionController.canPrint(url) else { throw ServiceError("系统无法打印此文件。TXT 请使用盒子打印入口。") }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "Scan Center"
        info.duplex = .none
        controller.printInfo = info
        controller.printingItem = url
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else {
            throw ServiceError("无法打开系统打印面板。")
        }
        controller.present(from: CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 1, height: 1), in: window, animated: true)
    }
}

struct PrintView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importing = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var preparing = false
    @State private var confirmPrint = false
    @State private var confirmReceipt = false
    @State private var compose = false
    @State private var text = ""
    var locked: Bool { model.printing || model.printReceipt != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("把文件交给 Brother", systemImage: "printer.fill").font(.headline)
                    Text("PDF、照片和文字都可以从手机发送。").foregroundStyle(.secondary)
                    Button { importing = true } label: { Label("从文件中选择", systemImage: "folder") }.disabled(locked || preparing)
                    PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("选择照片", systemImage: "photo.on.rectangle") }.disabled(locked || preparing)
                    Button { compose = true } label: { Label("输入文字", systemImage: "text.cursor") }.disabled(locked || preparing)
                    if preparing { ProgressView("正在本机准备文件") }
                    if model.printFile != nil { LabeledContent("已选择", value: model.printName) }
                }
                Section {
                    Button { if let url = model.printFile { do { try PrintPreparation.airPrint(url) } catch { model.error = model.readable(error) } } } label: {
                        Label("用 AirPrint 打印", systemImage: "airplayaudio")
                    }.disabled(model.printFile == nil || preparing || locked)
                } footer: { Text("打开 iOS 系统打印面板，选择家中的 Brother 打印机。") }
                Section("通过 HiNAS 打印") {
                    Button("读取打印机参数") { Task { await model.loadPrintCapabilities() } }.disabled(locked)
                    if let caps = model.printCaps {
                        Text(caps.message).font(.footnote).foregroundStyle(.secondary)
                        Picker("纸张", selection: $model.printOptions.media) {
                            ForEach(caps.papers) { Text($0.label).tag($0.value) }
                        }
                        Picker("质量", selection: $model.printOptions.quality) {
                            Text("标准").tag("standard")
                            if caps.hq { Text("HQ 高质量").tag("hq") }
                            Text("节省碳粉").tag("toner-save")
                        }
                        Picker("方向", selection: $model.printOptions.orientation) { Text("纵向").tag("portrait"); Text("横向").tag("landscape") }
                        Picker("缩放", selection: $model.printOptions.scale) { Text("适合纸张").tag("fit"); Text("实际大小").tag("none") }
                        Stepper("\(model.printOptions.copies) 份", value: $model.printOptions.copies, in: 1...20)
                        TextField("页码，例如 1,3-5，留空为全部", text: $model.printOptions.pages).keyboardType(.numbersAndPunctuation)
                        Text("单面打印").foregroundStyle(.secondary)
                        Button("发送到打印机") { confirmPrint = true }
                            .disabled(!caps.ready || model.printFile == nil || locked || preparing)
                    }
                }.disabled(model.printing)
                Section {
                    Text(model.printStatus).font(.subheadline)
                    if let value = model.printProgress { ProgressView(value: value) { Text("发送进度") } }
                    if model.printReceipt != nil {
                        Button("查询这份任务的回执") { Task { await model.checkPrintReceipt() } }.disabled(model.printing)
                        Button("结束跟踪，准备下一份") { confirmReceipt = true }.disabled(model.printing)
                    }
                } footer: { Text("发送进度表示文件传输。出纸状态由 CUPS 回执提供。发送结果不确定时，请先查询回执。") }
            }
            .navigationTitle("打印")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .plainText]) { result in
                switch result {
                case .success(let url): prepare(url)
                case .failure(let error): model.error = model.readable(error)
                }
            }
            .onChange(of: selectedPhoto) { item in
                guard let item else { return }
                preparing = true
                Task {
                    defer { preparing = false; selectedPhoto = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), data.count <= 120 * 1024 * 1024 else { throw ServiceError("照片无法读取或超过大小上限。") }
                        let input = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".image")
                        try data.write(to: input, options: .atomic)
                        defer { try? FileManager.default.removeItem(at: input) }
                        let result = try await Task.detached { try PrintPreparation.prepare(input) }.value
                        replaceFile(result, name: "照片.pdf")
                    } catch { model.error = model.readable(error) }
                }
            }
            .sheet(isPresented: $compose) {
                NavigationStack {
                    TextEditor(text: $text).padding().navigationTitle("输入文字")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("取消") { compose = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("使用文字") {
                                    do {
                                        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
                                        try Data(text.utf8).write(to: file, options: .atomic)
                                        replaceFile(file, name: "文字.txt"); compose = false
                                    } catch { model.error = model.readable(error) }
                                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.utf8.count > 131072)
                            }
                        }
                }
            }
            .confirmationDialog("确认打印这份文件？", isPresented: $confirmPrint, titleVisibility: .visible) {
                Button("打印 \(model.printOptions.copies) 份") { model.submitPrint() }
            } message: { Text("\(model.printName)\n使用当前纸张、质量与页码设置。") }
            .confirmationDialog("确认已检查任务状态？", isPresented: $confirmReceipt, titleVisibility: .visible) {
                Button("结束跟踪") { model.finishPrintReceipt() }
            } message: { Text("结束跟踪不会取消已提交的打印。请确认上一份状态后再提交下一份。") }
        }
    }

    private func prepare(_ url: URL) {
        preparing = true
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() }; preparing = false }
            do {
                let file = try await Task.detached { try PrintPreparation.prepare(url) }.value
                replaceFile(file, name: url.lastPathComponent)
            } catch { model.error = model.readable(error) }
        }
    }

    private func replaceFile(_ url: URL, name: String) {
        if let previous = model.printFile { try? FileManager.default.removeItem(at: previous) }
        model.printFile = url; model.printName = name
    }
}
