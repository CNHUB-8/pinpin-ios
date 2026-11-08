import Foundation
import Combine

public enum PaletteError: Error, LocalizedError {
    case missingResource
    public var errorDescription: String? { "找不到内置 palette.json 色卡。" }
}

public enum Palette {
    public static func load(bundle: Bundle = .main) throws -> [BeadColor] {
        guard let url = bundle.url(forResource: "palette", withExtension: "json") else {
            throw PaletteError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }
    public static func decode(_ data: Data) throws -> [BeadColor] {
        let colors = try JSONDecoder().decode([BeadColor].self, from: data)
        guard !colors.isEmpty else { throw PatternError.paletteEmpty }
        var seen = Set<String>()
        for color in colors {
            guard !color.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, color.id.count <= 64 else { throw PatternError.invalidColorID }
            guard seen.insert(color.id).inserted else { throw PatternError.duplicateColorID(color.id) }
            _ = try ColorMatching.rgb(hex: color.hex)
        }
        return colors
    }
}

/// Atomic JSON persistence; failed loading/writing leaves in-memory state intact.
@MainActor public final class PatternStore: ObservableObject {
    @Published public private(set) var patterns: [Pattern] = []
    public let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private static let maximumFileBytes = 64 * 1024 * 1024
    public init(directoryURL: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Documents", isDirectory: true)
        self.directoryURL = directoryURL ?? documents.appendingPathComponent("BeadStudioPatterns", isDirectory: true)
        encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }
    public var fileURL: URL { directoryURL.appendingPathComponent("patterns.json") }
    public func load() throws {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path) }
        catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain &&
                [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code) {
                patterns = []; return
            }
            throw error
        }
        guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= Self.maximumFileBytes else { throw PatternError.fileTooLarge }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= Self.maximumFileBytes else { throw PatternError.fileTooLarge }
        let next = try decoder.decode([Pattern].self, from: data).map { try $0.validated() }
        guard Set(next.map(\.id)).count == next.count else { throw PatternError.duplicatePatternID }
        patterns = ordered(next)
    }
    public func save(_ pattern: Pattern) throws {
        let value = try pattern.validated()
        var next = patterns.filter { $0.id != value.id }; next.append(value)
        try persist(ordered(next))
    }
    public func delete(_ pattern: Pattern) throws { try delete(id: pattern.id) }
    public func delete(id: UUID) throws { try persist(patterns.filter { $0.id != id }) }
    private func ordered(_ values: [Pattern]) -> [Pattern] {
        values.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }
    }
    private func persist(_ next: [Pattern]) throws {
        let data = try encoder.encode(next)
        guard data.count <= Self.maximumFileBytes else { throw PatternError.fileTooLarge }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        patterns = next
    }
}
