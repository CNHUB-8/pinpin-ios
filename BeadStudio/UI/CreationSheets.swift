import SwiftUI
import UIKit

struct BlankPatternSheet: View {
    @Environment(\.dismiss) private var dismiss
    let create: (Pattern) throws -> Void
    @State private var title = "新图纸"
    @State private var width = 32
    @State private var height = 32
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("作品信息") { TextField("名称", text: $title) }
                Section("画布尺寸") {
                    Stepper("宽度：\(width) 格", value: $width, in: 16...128)
                    Stepper("高度：\(height) 格", value: $height, in: 16...128)
                    Text("共 \(width * height) 个位置，透明格不计入用豆数量。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("空白画布").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("创建") {
                        do {
                            try create(Pattern(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新图纸" : title,
                                               width: width, height: height, cells: Array(repeating: nil, count: width * height)))
                        } catch { errorMessage = error.localizedDescription }
                    } }
                }
        }.studioError($errorMessage)
    }
}

struct ImagePatternSheet: View {
    @Environment(\.dismiss) private var dismiss
    let data: Data
    let palette: [BeadColor]
    let create: (Pattern) throws -> Void
    @State private var title = "照片图纸"
    @State private var width = 48.0
    @State private var maximumColors = 24
    @State private var generating = false
    @State private var errorMessage: String?
    @State private var generationTask: Task<Void, Never>?

    private var image: UIImage? { UIImage(data: data) }
    private var dimensions: (width: Int, height: Int) {
        let ratio = (image?.size.height ?? 1) / max(image?.size.width ?? 1, 1)
        return (Int(width), min(128, max(1, Int((width * ratio).rounded()))))
    }
    var body: some View {
        NavigationStack {
            Form {
                if let image {
                    Section { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity) }
                }
                Section("转换设置") {
                    TextField("名称", text: $title)
                    Slider(value: $width, in: 16...128, step: 1) { Text("宽度") }
                    Text("图纸：\(dimensions.width) × \(dimensions.height) 格")
                    Stepper("最多 \(maximumColors) 种颜色", value: $maximumColors, in: 2...min(64, max(2, palette.count)))
                    Text("优先保持照片比例，高度最多 128 格。极高的照片会压缩至此上限。透明区域保留为空白。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button { generate() } label: {
                        HStack { Spacer(); if generating { ProgressView() }; Text(generating ? "正在转换…" : "生成图纸"); Spacer() }
                    }.disabled(generating || palette.isEmpty)
                }
            }
            .disabled(generating)
            .navigationTitle("照片转图纸").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { generationTask?.cancel(); dismiss() } } }
            .interactiveDismissDisabled(generating)
        }.studioError($errorMessage)
    }

    private func generate() {
        generating = true
        let payload = data
        let w = dimensions.width, h = dimensions.height, limit = maximumColors
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "照片图纸" : title
        generationTask = Task { @MainActor in
            defer { generating = false }
            do {
                // Pass only Sendable Data across the worker boundary. UIKit image decoding
                // and core quantization stay off the main thread; store updates stay on it.
                let encodedPalette = try JSONEncoder().encode(palette)
                let encodedPattern = try await Task.detached(priority: .userInitiated) {
                    guard let image = UIImage(data: payload) else { throw StudioUIError.invalidImage }
                    let colors = try JSONDecoder().decode([BeadColor].self, from: encodedPalette)
                    let result = try PatternGenerator.generate(from: image, title: name, width: w, height: h,
                                                               palette: colors, maximumColors: limit)
                    return try JSONEncoder().encode(result)
                }.value
                try Task.checkCancellation()
                let pattern = try JSONDecoder().decode(Pattern.self, from: encodedPattern).validated()
                try create(pattern)
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
