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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("darkAppearance") private var dark = false
    var body: some View {
        TabView(selection: $model.tab) {
            ScanView().tabItem { Label("扫描", systemImage: "scanner") }.tag(0)
            DocumentsView().tabItem { Label("文档", systemImage: "doc.on.doc") }.tag(1)
            PrintView().tabItem { Label("打印", systemImage: "printer") }.tag(2)
            ConnectionView().tabItem { Label("设备", systemImage: "wifi") }.tag(3)
        }
        .adaptiveNavigation()
        .tint(Color(red: 0.16, green: 0.48, blue: 0.36))
        .preferredColorScheme(dark ? .dark : .light)
        .environment(\.dynamicTypeSize, CommandLine.arguments.contains("--large-type") ? .accessibility2 : dynamicTypeSize)
        .onAppear {
            if let index = CommandLine.arguments.firstIndex(of: "--screen"), CommandLine.arguments.count > index + 1,
               let tab = Int(CommandLine.arguments[index + 1]), (0...3).contains(tab) { model.tab = tab }
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var source: ScanSource = .feeder
    @State private var dpi = 600
    @State private var clearConfirmation = false
    var resolutions: [Int] { model.capabilities?.resolutions(for: source) ?? [300, 600] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "scanner").font(.largeTitle).foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Brother MFC-1819").font(.headline)
                            Text(model.connected ? "HiNAS 已连接" : "等待连接 HiNAS")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8).accessibilityElement(children: .combine)
                }
                Section("扫描来源") {
                    Picker("扫描来源", selection: $source) {
                        ForEach(ScanSource.allCases) { item in Text(item.title).tag(item) }
                    }.pickerStyle(.segmented)
                }.disabled(model.busy || model.pending != nil)
                Section {
                    Picker("分辨率", selection: $dpi) {
                        ForEach(resolutions, id: \.self) { Text("\($0) dpi").tag($0) }
                    }
                    LabeledContent("原稿尺寸", value: "A4")
                    LabeledContent("色彩", value: "24 位彩色")
                    LabeledContent("扫描面", value: "单面")
                } header: { Text("图像") } footer: {
                    Text(dpi == 600 ? "600 dpi 适合细字和存档，采集与传输耗时更长。" : "扫描原图会按当前分辨率保存在手机中。")
                }.disabled(model.busy || model.pending != nil)
                Section {
                    Label(source == .feeder ? "放入顶部托盘" : "放在玻璃上", systemImage: source.icon)
                        .font(.headline)
                    Text(source == .feeder
                         ? "正面朝下，顶端先入。每批最多放入 10 张 A4 原稿。"
                         : "先取出顶部托盘中的原稿，再将待扫描的一页放在玻璃上。")
                        .foregroundStyle(.secondary)
                }
                Section {
                    HStack(spacing: 12) {
                        if model.busy { ProgressView().accessibilityLabel("扫描进行中") }
                        Text(model.status)
                    }
                    if let value = model.progress {
                        ProgressView(value: value) { Text("接收原图") }
                            .animation(reduceMotion ? nil : .easeInOut, value: value)
                    }
                    if model.pending != nil && !model.busy {
                        Button("已检查设备，结束此次接收") { clearConfirmation = true }
                    }
                }
            }
            .navigationTitle("扫描")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actions.padding(.horizontal, 20).padding(.vertical, 12)
                    .frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .onChange(of: source) { _ in normalizeDPI() }
            .onChange(of: model.connected) { _ in
                if model.capabilities?.supportsFeeder != true { source = .flatbed }
                normalizeDPI()
            }
            .confirmationDialog("确认已检查盒子任务？", isPresented: $clearConfirmation, titleVisibility: .visible) {
                Button("结束接收记录", role: .destructive) { model.clearPendingAfterCheck() }
            } message: {
                Text("结束接收记录不会停止设备。请先确认原稿与在途扫描状态，再发起下一次扫描。")
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if !model.connected {
            Button { model.tab = 3 } label: {
                Label("连接设备", systemImage: "wifi").frame(maxWidth: .infinity, minHeight: 28)
            }.nativePrimaryAction().disabled(model.busy)
        } else if let pending = model.pending {
            HStack(spacing: 12) {
                if !model.busy && pending.jobID != nil {
                    Button { model.resume() } label: {
                        Label("继续接收", systemImage: "arrow.down.doc").frame(maxWidth: .infinity, minHeight: 28)
                    }.nativePrimaryAction()
                }
                if pending.jobID != nil {
                    Button(role: .destructive) { Task { await model.cancel() } } label: {
                        Label("停止扫描", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 28)
                    }.nativeSecondaryAction()
                }
            }
        } else {
            Button { model.start(source: source, dpi: dpi) } label: {
                Label(source == .feeder ? "自动进稿扫描" : "平板扫描", systemImage: source.icon)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }.nativePrimaryAction()
                .disabled(model.busy || (source == .feeder && model.capabilities?.supportsFeeder != true))
        }
    }

    private func normalizeDPI() {
        if !resolutions.contains(dpi), let last = resolutions.last { dpi = last }
    }
}
