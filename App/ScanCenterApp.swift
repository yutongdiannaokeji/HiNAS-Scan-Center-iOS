import SwiftUI

@MainActor final class LaunchState: ObservableObject {
    let model: AppModel?
    let error: String?
    init() {
        do { model = AppModel(library: try DocumentLibrary()); error = nil }
        catch { model = nil; self.error = "无法打开本机文档库。请先在“文件”App 中备份 Scan Center 文件，再重新打开。\n" + error.localizedDescription }
    }
}

@main struct ScanCenterApp: App {
    @StateObject private var launch = LaunchState()
    var body: some Scene {
        WindowGroup {
            if let model = launch.model {
                RootView().environmentObject(model).environmentObject(model.library)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                    Text(launch.error ?? "文档库无法打开").multilineTextAlignment(.center)
                }.padding(30)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("darkAppearance") private var dark = false
    var body: some View {
        TabView(selection: $model.tab) {
            ScanView().tabItem { Label("扫描", systemImage: "scanner") }.tag(0)
            DocumentsView().tabItem { Label("文档", systemImage: "doc.on.doc") }.tag(1)
            PrintView().tabItem { Label("打印", systemImage: "printer") }.tag(2)
            ConnectionView().tabItem { Label("设备", systemImage: "wifi") }.tag(3)
        }
        .tint(Color(red: 0.16, green: 0.48, blue: 0.36))
        .preferredColorScheme(dark ? .dark : .light)
        .alert("请检查", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

struct ConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("darkAppearance") private var dark = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Brother MFC-1819", systemImage: "printer.fill").font(.headline)
                    Label(model.connected ? "已连接 HiNAS" : "等待连接", systemImage: model.connected ? "checkmark.circle.fill" : "wifi")
                        .foregroundStyle(model.connected ? Color.green : Color.secondary)
                }
                Section("盒子地址") {
                    TextField("192.168.31.47", text: $model.host).keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack { Text("端口"); Spacer(); TextField("8088", value: $model.port, format: .number.grouping(.never)).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                }.disabled(model.busy || model.printing)
                Section {
                    TextField("账号", text: $model.user).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("HiNAS 管理密码", text: $model.password).textContentType(.password)
                    Button { Task { await model.connect() } } label: {
                        HStack { Text(model.connected ? "重新连接" : "连接设备"); Spacer(); if model.busy { ProgressView() } }
                    }.disabled(model.busy || model.password.isEmpty)
                } header: { Text("扫描权限") } footer: { Text("沿用 HiNAS 管理页账号。密码只在本次连接时使用。请在可信家庭局域网使用。") }
                if let caps = model.capabilities {
                    Section("设备能力") {
                        LabeledContent("自动进稿", value: caps.supportsFeeder ? "每批最多 10 页" : "当前未开放")
                        LabeledContent("最高进稿分辨率", value: "\(caps.scan_center_api?.adf_max_dpi ?? 0) dpi")
                        LabeledContent("采集", value: "24 位彩色")
                    }
                }
                Section { Toggle("深色外观", isOn: $dark) }
                Section {
                    Text("本机文档可在“文件”App 的 Scan Center 目录中访问。扫描期间请保持 App 在前台，离开后可重新连接并继续接收同一任务。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设备")
        }
    }
}

struct ScanView: View {
    @EnvironmentObject private var model: AppModel
    @State private var source: ScanSource = .feeder
    @State private var dpi = 600
    @State private var clearConfirmation = false
    var resolutions: [Int] { model.capabilities?.resolutions(for: source) ?? [300, 600] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("纸上的故事，\n好好收起来。").font(.system(size: 31, weight: .semibold, design: .rounded))
                            Text("Brother MFC-1819").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "doc.text.viewfinder").font(.system(size: 43, weight: .light)).foregroundStyle(.tint).padding(.top, 8)
                    }
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 26))

                    if !model.connected {
                        Button { model.tab = 3 } label: { Label("连接家中的 HiNAS", systemImage: "wifi") .frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        Text("扫描设置").font(.headline)
                        Picker("扫描来源", selection: $source) {
                            ForEach(ScanSource.allCases) { value in
                                Label(value.title, systemImage: value.icon).tag(value)
                            }
                        }.pickerStyle(.segmented)
                        Picker("分辨率", selection: $dpi) { ForEach(resolutions, id: \.self) { Text("\($0) dpi").tag($0) } }
                        LabeledContent("原稿", value: "A4 · 彩色 · 单面")
                        Text(source == .feeder ? "原稿放入顶部托盘，正面朝下，顶端先入。每批最多 10 张。" : "先取出顶部托盘的原稿，再将原稿放在玻璃上。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if dpi == 600 { Text("600 dpi 保留细字与图像细节，采集和传输需要更长时间。") .font(.footnote).foregroundStyle(.secondary) }
                    }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 22))
                    .disabled(model.busy || model.pending != nil)
                    if model.pending == nil {
                        Button { model.start(source: source, dpi: dpi) } label: {
                            Label(source == .feeder ? "自动进稿扫描" : "平板扫描", systemImage: source.icon).frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.connected || model.busy || (source == .feeder && model.capabilities?.supportsFeeder != true))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { if model.busy { ProgressView() }; Text(model.status).font(.subheadline) }
                        if let progress = model.progress { ProgressView(value: progress).animation(.easeInOut, value: progress) }
                        if let pending = model.pending {
                            if !model.busy, pending.jobID != nil {
                                Button("继续接收原图") { model.resume() }.disabled(!model.connected)
                            }
                            if pending.jobID != nil {
                                Button("停止盒子扫描", role: .destructive) { Task { await model.cancel() } }.disabled(!model.connected)
                            }
                            if !model.busy { Button("已检查设备，结束此次接收") { clearConfirmation = true }.font(.footnote) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(20).frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Scan Center").navigationBarTitleDisplayMode(.inline)
            .onChange(of: source) { _ in normalizeDPI() }
            .onChange(of: model.connected) { _ in
                if model.capabilities?.supportsFeeder != true { source = .flatbed }
                normalizeDPI()
            }
            .confirmationDialog("确认已检查盒子任务？", isPresented: $clearConfirmation, titleVisibility: .visible) {
                Button("结束接收记录", role: .destructive) { model.clearPendingAfterCheck() }
            } message: { Text("结束接收记录不会停止设备。请先确认原稿与在途扫描状态，再发起下一次扫描。") }
        }
    }
    private func normalizeDPI() { if !resolutions.contains(dpi), let last = resolutions.last { dpi = last } }
}
