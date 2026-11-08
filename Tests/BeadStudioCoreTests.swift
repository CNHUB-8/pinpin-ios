import XCTest
import UIKit
@testable import BeadStudio

final class BeadStudioCoreTests: XCTestCase {
    private let colors = [BeadColor(id: "R", hex: "#FF0000"),
                          BeadColor(id: "G", hex: "#00FF00"),
                          BeadColor(id: "B", hex: "#0000FF")]

    func testPatternValidationAndCounts() throws {
        let pattern = Pattern(title: "测试", width: 2, height: 2,
                              cells: ["R", nil, "R", "B"], completed: ["R"])
        XCTAssertEqual(try pattern.validated().counts, ["R": 2, "B": 1])
        var invalid = pattern; invalid.completed.insert("missing")
        XCTAssertThrowsError(try invalid.validated())
        invalid = pattern; invalid.cells.removeLast()
        XCTAssertThrowsError(try invalid.validated())
        invalid = pattern; invalid.width = 257
        XCTAssertThrowsError(try invalid.validated())
        invalid = pattern; invalid.title = " "
        XCTAssertThrowsError(try invalid.validated())
        invalid = pattern; invalid.cells[0] = String(repeating: "x", count: 65)
        XCTAssertThrowsError(try invalid.validated())
    }

    func testPaletteValidation() throws {
        let valid = Data("[{\"id\":\"A\",\"hex\":\"#0fAB23\"}]".utf8)
        XCTAssertEqual(try Palette.decode(valid).first?.id, "A")
        for bad in ["[]", "{}", "[{\"id\":\"A\",\"hex\":\"red\"}]",
                    "[{\"id\":\"A\",\"hex\":\"000000\"},{\"id\":\"A\",\"hex\":\"FFFFFF\"}]"] {
            XCTAssertThrowsError(try Palette.decode(Data(bad.utf8)))
        }
    }

    func testLabKnownReferenceValues() throws {
        let black = ColorMatching.lab(try ColorMatching.rgb(hex: "000000"))
        let white = ColorMatching.lab(try ColorMatching.rgb(hex: "FFFFFF"))
        let red = ColorMatching.lab(try ColorMatching.rgb(hex: "FF0000"))
        XCTAssertEqual(black.l, 0, accuracy: 0.0001)
        XCTAssertEqual(white.l, 100, accuracy: 0.001)
        XCTAssertEqual(red.l, 53.2408, accuracy: 0.001)
        XCTAssertEqual(red.a, 80.0925, accuracy: 0.001)
        XCTAssertEqual(red.b, 67.2032, accuracy: 0.001)
        XCTAssertEqual(ColorMatching.distanceSquared(red, red), 0)
        XCTAssertThrowsError(try ColorMatching.rgb(hex: "#FFFFFF00"))
    }

    private func image(width: Int, height: Int, pixels: [UIColor?]) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: CGFloat(width), height: CGFloat(height)), format: format).image { context in
            for (index, color) in pixels.enumerated() {
                guard let color else { continue }
                context.cgContext.setFillColor(color.cgColor)
                context.cgContext.fill(CGRect(x: CGFloat(index % width), y: CGFloat(index / width), width: 1, height: 1))
            }
        }
    }

    func testImageTransparencyAndCellOrder() throws {
        let source = image(width: 2, height: 2, pixels: [.red, nil, .green, .blue])
        let pattern = try PatternGenerator.generate(from: source, width: 2, height: 2, palette: colors)
        XCTAssertEqual(pattern.cells, ["R", nil, "G", "B"])
        XCTAssertEqual(pattern.counts.values.reduce(0, +), 3)
    }

    func testPremultipliedAlphaIsRecovered() throws {
        let source = image(width: 1, height: 1, pixels: [UIColor.red.withAlphaComponent(0.5)])
        let palette = [BeadColor(id: "dark", hex: "800000"), BeadColor(id: "red", hex: "FF0000")]
        let pattern = try PatternGenerator.generate(from: source, width: 1, height: 1, palette: palette)
        XCTAssertEqual(pattern.cells, ["red"])
        let skipped = try PatternGenerator.generate(from: source, width: 1, height: 1,
                                                    palette: palette, alphaThreshold: 0.9)
        XCTAssertEqual(skipped.cells, [nil])
    }

    func testColorLimitPreservesTransparency() throws {
        let source = image(width: 4, height: 1, pixels: [.red, .red, .blue, nil])
        let pattern = try PatternGenerator.generate(from: source, width: 4, height: 1,
                                                    palette: colors, maximumColors: 1)
        XCTAssertEqual(pattern.cells, ["R", "R", "R", nil])
        XCTAssertThrowsError(try PatternGenerator.generate(from: source, width: 4, height: 1,
                                                           palette: colors, maximumColors: 0))
        XCTAssertThrowsError(try PatternGenerator.generate(from: source, width: 4, height: 1,
                                                           palette: colors, alphaThreshold: .nan))
    }

    func testUIImageMirroringIsHonored() throws {
        let source = image(width: 2, height: 1, pixels: [.red, .blue])
        let mirrored = UIImage(cgImage: try XCTUnwrap(source.cgImage), scale: 1, orientation: .upMirrored)
        let pattern = try PatternGenerator.generate(from: mirrored, width: 2, height: 1, palette: colors)
        XCTAssertEqual(pattern.cells, ["B", "R"])
    }

    @MainActor func testAtomicStoreRoundtripAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PatternStore(directoryURL: directory)
        try store.load(); XCTAssertTrue(store.patterns.isEmpty)
        let pattern = Pattern(title: "保存", width: 2, height: 1, cells: ["R", nil], completed: ["R"])
        try store.save(pattern)
        let second = PatternStore(directoryURL: directory); try second.load()
        XCTAssertEqual(second.patterns, [pattern])
        var revised = pattern; revised.title = "更新"
        try second.save(revised); XCTAssertEqual(second.patterns.count, 1)
        try second.delete(id: pattern.id)
        try store.load(); XCTAssertTrue(store.patterns.isEmpty)
    }

    @MainActor func testCorruptLoadAndFailedWritePreserveMemory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PatternStore(directoryURL: directory)
        let pattern = Pattern(title: "保留", width: 1, height: 1, cells: ["R"])
        try store.save(pattern)
        try Data("corrupt".utf8).write(to: store.fileURL, options: .atomic)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(store.patterns, [pattern])
        try FileManager.default.removeItem(at: directory)
        try Data("directory obstruction".utf8).write(to: directory)
        XCTAssertThrowsError(try store.save(Pattern(title: "失败", width: 1, height: 1, cells: ["B"])))
        XCTAssertEqual(store.patterns, [pattern])
    }
}
