# 拼拼豆 iOS 重写（个人离线版）

本目录是基于 `拼拼豆-v1.8.0.apk` 静态分析后独立编写的 SwiftUI 原型工程源码。已确认 APK 包含 MARD 颜色数据、图纸/图层本地模型、图片识别与云端 API；本实现只使用可重新实现的离线核心，不复制 APK 代码，也不绕过登录、会员或云端服务。

## 当前范围

- 从照片生成固定网格拼豆图纸（Lab 感知色差匹配）
- MARD 颜色表、颜色统计、手动编辑、完成标记
- 本地 JSON 保存/导入/导出
- PNG 预览分享
- SwiftUI iOS 17 界面

## 构建

在 macOS 上用 Xcode 16 或更高版本新建 iOS App（SwiftUI，iOS 17），将 `BeadStudio/` 下 Swift 文件和 `Resources/palette.json` 加入 target。Windows 无法运行 Xcode、编译或签名 iOS 应用；源码和算法可在迁移到 Mac 后编译验证。

也可以安装 XcodeGen 后，在本目录运行 `xcodegen generate`，打开生成的 `BeadStudio.xcodeproj`。选择自己的开发团队和唯一 Bundle ID，再选择 iPhone 运行。免费个人签名通常需要定期重新签名。

附有 `.github/workflows/ios.yml`：若将本目录作为独立仓库根目录上传，可手动触发 macOS 模拟器编译与 XCTest。该流程尚未上传或运行，不会生成可在手机安装的签名 IPA。

## 证据与限制

APK SHA-256、包信息及静态分析结果在 `analysis/identity.json` 和 `analysis/classes.json`。模型文件是加密的，云端接口和会员能力未实现；因此“完整复刻”不应被宣称为已完成。

颜色数据及许可证见 `analysis/bead-d2-NOTICE.txt` 与 `analysis/bead-d2-LICENSE.txt`。

## 验证状态

## 未签名 IPA 云端构建

新增 `.github/workflows/ipa.yml`，可在 GitHub Actions 手动运行 `Build unsigned iPhone IPA`。流程先运行模拟器测试，再编译 iphoneos arm64，打包 `Payload/BeadStudio.app` 并上传 `BeadStudio-unsigned-IPA`。下载 artifact ZIP 后解压得到 IPA，需自行签名才能安装。支持本目录作为仓库根目录，或仓库内的 `pinpin-ios/` 子目录。

当前尚未连接 GitHub 账户，流程未执行，尚无 IPA 产物。

## 已执行检查

已在 Windows 检查 303 个色号唯一且 HEX 有效，并逐条对比转换前后的 APK 色卡；所有证据 JSON 可解析。已人工审阅核心与 UI 接口。

已编写 9 个 XCTest，覆盖 Lab 参考值、透明像素、图片方向、限色、格式校验和文件故障，但尚未运行。没有 Xcode 编译、模拟器截图或真机验证结果，不能视为已经可安装使用。
