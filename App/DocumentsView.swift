import SwiftUI
import UIKit

struct ShareItem: Identifiable { let id = UUID(); let url: URL }
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct PageThumbnail: View {
    let url: URL
    var rotation = 0
    var maxPixels = 500
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().rotationEffect(.degrees(Double(rotation))) }
            else { Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary) }
        }
        .task(id: url) {
            let target = url, size = maxPixels
            image = await Task.detached(priority: .utility) {
                Thumbnails.image(target, maxPixels: size).map { UIImage(cgImage: $0) }
            }.value
        }
    }
}

struct DocumentsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: DocumentLibrary
    @State private var deleteID: UUID?
    var body: some View {
        NavigationStack {
            Group {
                if library.documents.isEmpty {
                    VStack(spacing: 15) {
                        Image(systemName: "doc.on.doc").font(.system(size: 44, weight: .light)).foregroundStyle(.tint)
                        Text("给重要文件一个家").font(.title3.weight(.semibold))
                        Text("扫描完成后，原图会保存在这里。").foregroundStyle(.secondary)
                        Button("去扫描") { model.tab = 0 }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(library.documents) { document in
                            NavigationLink { DocumentDetail(id: document.id) } label: {
                                HStack(spacing: 16) {
                                    Group {
                                        if let page = document.pages.first { PageThumbnail(url: library.pageURL(page, document: document.id), rotation: page.rotation) }
                                        else { Image(systemName: "doc.badge.clock").foregroundStyle(.secondary) }
                                    }.frame(width: 54, height: 70).background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 7))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(document.title).font(.headline)
                                        Text("\(document.pages.count) 页").foregroundStyle(.secondary)
                                        Text(document.created, style: .date).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 5)
                            }
                            .swipeActions { Button("删除", role: .destructive) { deleteID = document.id }.disabled(model.busy || model.pending?.documentID == document.id) }
                        }
                    }
                }
            }.navigationTitle("我的文档")
            .confirmationDialog("删除这份文档及本机原图？", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }), titleVisibility: .visible) {
                Button("删除文档", role: .destructive) {
                    do { if let id = deleteID { try library.remove(id) } } catch { model.error = model.readable(error) }
                    deleteID = nil
                }
            }
        }
    }
}

struct DocumentDetail: View {
    let id: UUID
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: DocumentLibrary
    @State private var sharing: ShareItem?
    @State private var exporting = false
    @State private var rename = false
    @State private var title = ""
    var document: ScanDocument? { library.document(id) }
    var locked: Bool { model.pending?.documentID == id }
    var body: some View {
        List {
            if let document {
                Section {
                    ForEach(Array(document.pages.enumerated()), id: \.element.id) { index, page in
                        NavigationLink {
                            ScrollView([.horizontal, .vertical]) {
                                PageThumbnail(url: library.pageURL(page, document: id), rotation: page.rotation, maxPixels: 2400)
                                    .frame(minWidth: 300, maxWidth: 1000, minHeight: 500)
                            }.navigationTitle("第 \(index + 1) 页")
                        } label: {
                            HStack(spacing: 18) {
                                PageThumbnail(url: library.pageURL(page, document: id), rotation: page.rotation).frame(width: 62, height: 85)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("第 \(index + 1) 页").font(.headline)
                                    Text("\(page.dpi) dpi · \(page.width) × \(page.height)").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                        .swipeActions(edge: .leading) {
                            Button { do { try library.rotate(page.id, document: id) } catch { model.error = model.readable(error) } } label: { Label("旋转", systemImage: "rotate.right") }.tint(.green).disabled(locked)
                        }
                        .swipeActions {
                            Button("删除页", role: .destructive) { do { try library.removePage(page.id, document: id) } catch { model.error = model.readable(error) } }.disabled(locked)
                        }
                        .contextMenu {
                            Button { sharing = ShareItem(url: library.pageURL(page, document: id)) } label: {
                                Label("分享 PNG 原图", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    .onMove { offsets, target in do { try library.reorder(offsets, to: target, document: id) } catch { model.error = model.readable(error) } }
                    .moveDisabled(locked)
                } footer: { Text("导出 PDF 保留每页原图像素。用编辑按钮调整页序，向右滑动页面可旋转。") }
                Section {
                    Button {
                        exporting = true
                        Task {
                            defer { exporting = false }
                            do { sharing = ShareItem(url: try await model.export(id)) } catch { model.error = model.readable(error) }
                        }
                    } label: {
                        HStack { Label("导出无损 PDF", systemImage: "square.and.arrow.up"); Spacer(); if exporting { ProgressView() } }
                    }.disabled(exporting || document.pages.isEmpty || locked)
                }
            }
        }
        .navigationTitle(document?.title ?? "文档").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { EditButton().disabled(locked) }
            ToolbarItem(placement: .navigationBarTrailing) { Button { title = document?.title ?? ""; rename = true } label: { Image(systemName: "pencil") } }
        }
        .sheet(item: $sharing) { ActivitySheet(items: [$0.url]) }
        .alert("文档名称", isPresented: $rename) {
            TextField("名称", text: $title)
            Button("保存") { do { try library.rename(id, title: title) } catch { model.error = model.readable(error) } }
            Button("取消", role: .cancel) {}
        }
    }
}
