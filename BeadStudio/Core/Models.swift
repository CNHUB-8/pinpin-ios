import Foundation

public struct BeadColor: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let hex: String
    public init(id: String, hex: String) { self.id = id; self.hex = hex }
}

public struct Pattern: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var width: Int
    public var height: Int
    /// Row-major color IDs; nil is a transparent/empty cell.
    public var cells: [String?]
    /// Completed color IDs, not cell coordinates.
    public var completed: Set<String>
    public var updatedAt: Date
    public static let maximumDimension = 256

    public init(id: UUID = UUID(), title: String, width: Int, height: Int,
                cells: [String?], completed: Set<String> = [], updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.width = width; self.height = height
        self.cells = cells; self.completed = completed; self.updatedAt = updatedAt
    }

    @discardableResult public func validated() throws -> Pattern {
        guard width > 0, height > 0, width <= Self.maximumDimension, height <= Self.maximumDimension else {
            throw PatternError.invalidDimensions
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200 else {
            throw PatternError.invalidTitle
        }
        guard cells.count == width * height else {
            throw PatternError.invalidCellCount(expected: width * height, actual: cells.count)
        }
        guard cells.compactMap({ $0 }).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 64 }) else {
            throw PatternError.invalidColorID
        }
        guard completed.isSubset(of: Set(counts.keys)) else { throw PatternError.invalidCompletedEntry }
        guard updatedAt.timeIntervalSince1970.isFinite else { throw PatternError.invalidDate }
        return self
    }

    public var counts: [String: Int] {
        cells.compactMap { $0 }.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}

public enum PatternError: Error, Equatable, LocalizedError {
    case invalidDimensions, invalidTitle
    case invalidCellCount(expected: Int, actual: Int)
    case invalidColorID, invalidCompletedEntry, invalidDate, invalidImage, paletteEmpty
    case invalidColor(String), duplicateColorID(String)
    case invalidMaximumColors, invalidAlphaThreshold, duplicatePatternID, fileTooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidDimensions: return "图纸宽高必须为 1–256。"
        case .invalidTitle: return "标题需为 1–200 个字符。"
        case .invalidCellCount(let expected, let actual): return "图纸需要 \(expected) 格，实际为 \(actual) 格。"
        case .invalidColorID: return "颜色编号需为 1–64 个字符。"
        case .invalidCompletedEntry: return "完成标记包含图纸中不存在的颜色。"
        case .invalidDate: return "图纸日期无效。"
        case .invalidImage: return "无法读取图片。"
        case .paletteEmpty: return "色卡不能为空。"
        case .invalidColor(let value): return "无效颜色：\(value)"
        case .duplicateColorID(let value): return "重复颜色编号：\(value)"
        case .invalidMaximumColors: return "最大颜色数量必须大于零。"
        case .invalidAlphaThreshold: return "透明度阈值必须介于 0 和 1。"
        case .duplicatePatternID: return "保存文件包含重复图纸编号。"
        case .fileTooLarge: return "图纸文件过大。"
        }
    }
}
