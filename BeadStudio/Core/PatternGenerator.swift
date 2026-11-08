import UIKit
import CoreGraphics

public enum PatternGenerator {
    /// Orientation-correct CoreGraphics downsampling and CIE Lab nearest color.
    /// A color cap retains the most-used palette colors and rematches opaque cells.
    public static func generate(from image: UIImage, title: String = "新图纸", width: Int, height: Int,
                                palette: [BeadColor], maximumColors: Int? = nil,
                                alphaThreshold: Double = 0.15) throws -> Pattern {
        guard width > 0, height > 0, width <= Pattern.maximumDimension, height <= Pattern.maximumDimension else { throw PatternError.invalidDimensions }
        guard image.size.width > 0, image.size.height > 0 else { throw PatternError.invalidImage }
        guard !palette.isEmpty else { throw PatternError.paletteEmpty }
        if let maximumColors, maximumColors < 1 { throw PatternError.invalidMaximumColors }
        guard alphaThreshold.isFinite, (0...1).contains(alphaThreshold) else { throw PatternError.invalidAlphaThreshold }
        var seen = Set<String>()
        let labs = try palette.map { color -> ColorMatching.Lab in
            guard !color.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, color.id.count <= 64 else { throw PatternError.invalidColorID }
            guard seen.insert(color.id).inserted else { throw PatternError.duplicateColorID(color.id) }
            return ColorMatching.lab(try ColorMatching.rgb(hex: color.hex))
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        format.preferredRange = .standard
        let size = CGSize(width: CGFloat(width), height: CGFloat(height))
        let bounds = CGRect(origin: .zero, size: size)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let normalized = renderer.image { context in
            context.cgContext.interpolationQuality = .high
            image.draw(in: bounds)
        }
        guard let cgImage = normalized.cgImage, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw PatternError.invalidImage }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(cgImage, in: bounds)
            return true
        }
        guard rendered else { throw PatternError.invalidImage }
        var samples = [ColorMatching.Lab?](repeating: nil, count: width * height)
        var assignments = [Int?](repeating: nil, count: width * height)
        var frequencies = [Int](repeating: 0, count: palette.count)
        func nearest(_ sample: ColorMatching.Lab, candidates: [Int]) -> Int {
            var winner = candidates[0]
            var distance = ColorMatching.distanceSquared(sample, labs[winner])
            for candidate in candidates.dropFirst() {
                let next = ColorMatching.distanceSquared(sample, labs[candidate])
                if next < distance { winner = candidate; distance = next }
            }
            return winner
        }
        let all = Array(palette.indices)
        for index in samples.indices {
            let offset = index * 4
            let alpha = Double(rgba[offset + 3]) / 255
            guard alpha > 0, alpha >= alphaThreshold else { continue }
            // Bitmap components are premultiplied; divide by alpha before matching.
            let rgb = ColorMatching.RGB(red: min(1, Double(rgba[offset]) / 255 / alpha),
                                        green: min(1, Double(rgba[offset + 1]) / 255 / alpha),
                                        blue: min(1, Double(rgba[offset + 2]) / 255 / alpha))
            let sample = ColorMatching.lab(rgb); samples[index] = sample
            let selected = nearest(sample, candidates: all)
            assignments[index] = selected; frequencies[selected] += 1
        }
        if let maximumColors {
            let used = all.filter { frequencies[$0] > 0 }.sorted {
                frequencies[$0] == frequencies[$1] ? $0 < $1 : frequencies[$0] > frequencies[$1]
            }
            if used.count > maximumColors {
                let selected = Array(used.prefix(maximumColors))
                for index in samples.indices {
                    if let sample = samples[index] { assignments[index] = nearest(sample, candidates: selected) }
                }
            }
        }
        return try Pattern(title: title, width: width, height: height,
                           cells: assignments.map { $0.map { palette[$0].id } }).validated()
    }
}
