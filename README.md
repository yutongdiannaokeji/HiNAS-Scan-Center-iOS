# Scan Center for iPhone and iPad

原生 SwiftUI 客户端，连接现有 HiNAS + Brother MFC-1819。最低 iOS/iPadOS 16。应用接入现有的 8088 服务。

使用 Xcode 26.3 和 iOS 26 SDK 构建，在 iOS 26 上使用系统 Liquid Glass 标签栏、工具栏和主操作按钮。iPad 使用可适应侧边栏的原生导航。旧版 iOS 使用对应的系统控件。界面采用动态字体、系统语义颜色、系统安全区域，并跟随减少动态效果、透明度和对比度等辅助功能设置。设计依据 [Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials) 与 [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)。

## 使用

1. iPhone/iPad 与 HiNAS 连接同一个家庭局域网。
2. 进入「设备」，填写盒子地址和端口。已有设备地址为 `192.168.31.47`，端口 `8088`。允许 iOS 的局域网访问提示。
3. 用 HiNAS 管理页账号连接扫描仪。密码仅用于当前连接。
4. 「扫描」页选择「自动进稿器」或「玻璃平板」，选择盒子实际提供的分辨率，最高 600 dpi。原稿 A4、彩色、单面。每批最多 10 页。
5. 扫描后进入「文档」，预览、旋转、调整页序、分享 PNG 原图或导出多页无损 PDF。PDF 直接嵌入原 PNG 的 Deflate 数据，保留原图像素。
6. 「打印」可选择 PDF、照片或 UTF-8 TXT。AirPrint 使用系统打印窗口。HiNAS 打印入口读取真实纸张和质量选项，提供文件上传进度和 CUPS 回执。盒子入口最多接收 16 MiB，较大 PDF 可使用 AirPrint。

600 dpi 文档较大，请保持 App 在前台等待接收。连接中断后，重新连接同一盒子并选择「继续接收原图」。启动回执不确定时先检查盒子任务。已收到的页面保存在文档库中。

文档保存在 App 的 Documents/Scans，可从「文件」App 访问。盒子里的临时扫描仍按原服务的保留规则清理。删除文档会删除该文档的本机原图。导出的共享 PDF 在 App 缓存目录，扫描原图保留在文档库。

## IPA 安装

构建输出 `ScanCenter-1.0.0-unsigned.ipa`，包含为真实 iPhone/iPad 编译的 arm64 应用。安装前需要使用自己的 Apple 账号或开发者证书签名。

在 Windows 上可使用 [Sideloadly 官方版](https://sideloadly.io/)，连接并信任 iPhone，将 IPA 拖入工具，用自己的 Apple 账号在本机完成签名和安装。免费账号通常需要每 7 天续签，工具支持自动续签。Apple 账号密码与验证码直接在安装工具里输入。

也可在 Mac 用 Xcode 打开生成的工程，将 Signing Team 设为自己的团队，再安装到连接的设备。注册设备分发需要匹配的证书及描述文件。详见 [Apple 设备安装说明](https://developer.apple.com/documentation/xcode/distributing-apps-to-your-development-devices)。

## 本机编译

需要带有 iOS 26 SDK 的 Xcode 26 或更新版本，以及 XcodeGen。编译目标最低 iOS 16。

```sh
brew install xcodegen
python3 tools/icon.py
xcodegen generate
xcodebuild -project ScanCenter.xcodeproj -scheme ScanCenter \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=arm64 build
python3 tools/package_ipa.py build/device/Build/Products/Release-iphoneos/ScanCenter.app dist
```

GitHub Actions 的 `Build iOS IPA` 工作流执行模拟器编译与测试、启动截图，再编译 iphoneos arm64 并校验 IPA 平台及 SHA-256。构建任务里可以下载 `ScanCenter-iOS` 附件。

## 验证范围

现有盒子的登录、扫描能力、600 dpi 进稿与打印参数接口已进行实时查询。iOS 客户端的真机局域网权限、扫描接收、系统分享及实际打印仍需安装后验收。协议测试和模拟器结果分别由构建日志记录。现阶段只使用既有接口，iOS 安装前无需更新 HiNAS。
