import SwiftUI
import UIKit

extension Array where Element == BeadColor {
    var hexByID: [String: String] { Dictionary(map { ($0.id, $0.hex) }, uniquingKeysWith: { first, _ in first }) }
}

extension Color {
    init(beadHex: String) { self.init(uiColor: UIColor(beadHex: beadHex)) }
    var legibleText: Color {
        let color = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.55 ? .black : .white
    }
}

extension UIColor {
    convenience init(beadHex: String) {
        let value = beadHex.hasPrefix("#") ? String(beadHex.dropFirst()) : beadHex
        guard value.count == 6, let number = UInt32(value, radix: 16) else { self.init(white: 0.5, alpha: 1); return }
        self.init(red: CGFloat((number >> 16) & 255) / 255,
                  green: CGFloat((number >> 8) & 255) / 255,
                  blue: CGFloat(number & 255) / 255, alpha: 1)
    }
    var contrastText: UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.55 ? .black : .white
    }
}

enum StudioUIError: LocalizedError {
    case invalidImage, fileTooLarge, unknownColor, pngEncoding, unsupportedDimensions
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取照片，请选择另一张图片。"
        case .fileTooLarge: return "JSON 文件超过 8 MB，无法导入。"
        case .unknownColor: return "图纸包含当前色卡没有的色号，无法导入。"
        case .pngEncoding: return "PNG 图纸生成失败。"
        case .unsupportedDimensions: return "此版本界面支持最大 128 × 128 格的图纸。"
        }
    }
}

extension View {
    func studioError(_ message: Binding<String?>) -> some View {
        alert("操作未完成", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("好", role: .cancel) { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "未知错误") }
    }
}

struct StudioShareItem: Identifiable {
    let id = UUID()
    let url: URL
    init(data: Data, filename: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BeadStudioShares", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
    }
    static func cleanExpired() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BeadStudioShares", isDirectory: true)
        guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for child in children {
            if let date = try? child.resourceValues(forKeys: [.creationDateKey]).creationDate,
               Date().timeIntervalSince(date) > 86_400 { try? FileManager.default.removeItem(at: child) }
        }
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Exports a portable PNG with a cell grid, color IDs and a material legend.
/// This does not depend on screenshots or any original APK resources.
@MainActor enum PatternPNG {
    static func render(_ pattern: Pattern, palette: [BeadColor]) throws -> Data {
        let colors = palette.hexByID
        let cell: CGFloat = min(24, 4096 / CGFloat(max(pattern.width, pattern.height)))
        let margin: CGFloat = 24
        let header: CGFloat = 70
        let width = max(CGFloat(pattern.width) * cell + margin * 2, 600)
        let columns = max(1, Int((width - margin * 2) / 150))
        let entries = pattern.counts.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        let legendRows = (entries.count + columns - 1) / columns
        let boardHeight = CGFloat(pattern.height) * cell
        let height = header + boardHeight + 48 + CGFloat(legendRows) * 30 + margin
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let output = renderer.image { rendering in
            let context = rendering.cgContext
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            (pattern.title as NSString).draw(in: CGRect(x: margin, y: 16, width: width - margin * 2, height: 28), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.black])
            let subtitle = "\(pattern.width) × \(pattern.height) 格 · \(entries.count) 色 · \(entries.reduce(0) { $0 + $1.value }) 颗"
            (subtitle as NSString).draw(at: CGPoint(x: margin, y: 44), withAttributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.darkGray])
            for (index, id) in pattern.cells.enumerated() {
                let rect = CGRect(x: margin + CGFloat(index % pattern.width) * cell,
                                  y: header + CGFloat(index / pattern.width) * cell, width: cell, height: cell)
                if let id, let hex = colors[id] {
                    let color = UIColor(beadHex: hex); color.setFill(); context.fill(rect)
                    let style = NSMutableParagraphStyle(); style.alignment = .center
                    (id as NSString).draw(in: CGRect(x: rect.minX, y: rect.minY + 7, width: cell, height: 12), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 8, weight: .medium), .foregroundColor: color.contrastText, .paragraphStyle: style])
                }
                context.setStrokeColor(UIColor.black.withAlphaComponent(0.22).cgColor)
                context.setLineWidth(0.5); context.stroke(rect)
            }
            let legendY = header + boardHeight + 18
            for (index, item) in entries.enumerated() {
                let x = margin + CGFloat(index % columns) * 150
                let y = legendY + CGFloat(index / columns) * 30
                UIColor(beadHex: colors[item.key] ?? "#808080").setFill()
                context.fill(CGRect(x: x, y: y, width: 18, height: 18))
                let text = "\(item.key)  × \(item.value)"
                (text as NSString).draw(at: CGPoint(x: x + 25, y: y + 1), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: UIColor.black])
            }
        }
        guard let data = output.pngData() else { throw StudioUIError.pngEncoding }
        return data
    }
}
