import Foundation

public enum ColorMatching {
    public struct RGB: Equatable, Sendable {
        public let red: Double; public let green: Double; public let blue: Double
        public init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }
    }
    public struct Lab: Equatable, Sendable { public let l: Double; public let a: Double; public let b: Double }
    /// Six-digit sRGB, with an optional leading #; no alpha or shorthand formats.
    public static func rgb(hex: String) throws -> RGB {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, digits.unicodeScalars.allSatisfy({
            (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value)
        }), let value = UInt32(digits, radix: 16) else { throw PatternError.invalidColor(hex) }
        return RGB(red: Double((value >> 16) & 255) / 255,
                   green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    /// IEC sRGB -> CIE Lab, D65 reference white.
    public static func lab(_ rgb: RGB) -> Lab {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        let r = linear(rgb.red), g = linear(rgb.green), b = linear(rgb.blue)
        let x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047
        let y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
        let z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883
        func f(_ value: Double) -> Double { value > 216.0 / 24389.0 ? pow(value, 1.0 / 3.0) : (24389.0 / 27.0 * value + 16.0) / 116.0 }
        return Lab(l: 116 * f(y) - 16, a: 500 * (f(x) - f(y)), b: 200 * (f(y) - f(z)))
    }
    public static func distanceSquared(_ lhs: Lab, _ rhs: Lab) -> Double {
        let l = lhs.l - rhs.l, a = lhs.a - rhs.a, b = lhs.b - rhs.b
        return l * l + a * a + b * b
    }
}
