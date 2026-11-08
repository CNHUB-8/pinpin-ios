import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var store = PatternStore()
    @State private var palette: [BeadColor] = []
    @State private var editing: Pattern?
    @State private var photoSelection: PhotosPickerItem?
    @State private var imageDraft: ImageDraft?
    @State private var showingBlank = false
    @State private var importingJSON = false
    @State private var errorMessage: String?
    @State private var loadingPhoto = false
    @State private var storageReady = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("把喜欢的颜色，变成一颗颗豆子。")
                            .font(.title3.weight(.semibold))
                        Text("照片转图纸 · 自由编辑 · 按色备料")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                }
                Section("我的作品 · \(store.patterns.count)") {
                    if store.patterns.isEmpty {
                        ContentUnavailableView("从第一张图纸开始", systemImage: "square.grid.3x3",
                                               description: Text("导入照片，或创建空白画布。作品只保存在此设备。"))
                    }
                    ForEach(store.patterns) { pattern in
                        Button { editing = pattern } label: {
                            HStack(spacing: 14) {
                                PatternThumbnail(pattern: pattern, colors: palette.hexByID)
                                    .frame(width: 64, height: 64)
                                    .background(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(pattern.title).font(.headline).foregroundStyle(.primary)
                                    Text("\(pattern.width) × \(pattern.height) · \(pattern.counts.count) 色")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(pattern.updatedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 4)
                        }.buttonStyle(.plain)
                        .swipeActions { Button(role: .destructive) {
                            do { try store.delete(pattern) } catch { errorMessage = error.localizedDescription }
                        } label: { Label("删除", systemImage: "trash") } }
                    }
                }
                Section {
                    Button { importingJSON = true } label: { Label("导入图纸 JSON", systemImage: "square.and.arrow.down") }.disabled(!storageReady || palette.isEmpty)
                    if !storageReady {
                        Button("重新读取本地作品") { loadLibrary() }
                        Text("本地作品尚未成功读取，已暂停创建与导入，避免覆盖现有文件。")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    Text("这是独立重写的个人图纸工具。JSON 导入仅支持本应用的数据格式。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("拼拼豆工坊")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PhotosPicker(selection: $photoSelection, matching: .images) {
                        Label("导入照片", systemImage: "photo.badge.plus")
                    }.disabled(!storageReady || palette.isEmpty || loadingPhoto)
                    Button { showingBlank = true } label: { Label("空白画布", systemImage: "plus") }
                        .disabled(!storageReady || palette.isEmpty)
                }
            }
            .overlay { if loadingPhoto { ProgressView("读取照片…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
        .tint(.indigo)
        .task {
            loadLibrary()
        }
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            loadingPhoto = true
            Task {
                defer { loadingPhoto = false; photoSelection = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else { throw StudioUIError.invalidImage }
                    imageDraft = ImageDraft(data: data)
                } catch { errorMessage = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showingBlank) {
            BlankPatternSheet { pattern in
                try store.save(pattern); showingBlank = false; openAfterSheet(pattern)
            }
        }
        .sheet(item: $imageDraft) { draft in
            ImagePatternSheet(data: draft.data, palette: palette) { pattern in
                try store.save(pattern)
                imageDraft = nil
                openAfterSheet(pattern)
            }
        }
        .fullScreenCover(item: $editing) { pattern in
            NavigationStack { PatternEditor(pattern: pattern, palette: palette, store: store) }
        }
        .fileImporter(isPresented: $importingJSON, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 8_000_000 else { throw StudioUIError.fileTooLarge }
                let raw = try Data(contentsOf: url)
                guard raw.count <= 8_000_000 else { throw StudioUIError.fileTooLarge }
                let decoded = try JSONDecoder().decode(Pattern.self, from: raw).validated()
                guard decoded.width <= 128, decoded.height <= 128 else { throw StudioUIError.unsupportedDimensions }
                let known = Set(palette.map(\.id))
                guard decoded.cells.compactMap({ $0 }).allSatisfy({ known.contains($0) }) else { throw StudioUIError.unknownColor }
                // Import as a new local work rather than overwriting an existing UUID.
                let imported = Pattern(title: decoded.title, width: decoded.width, height: decoded.height,
                                       cells: decoded.cells, completed: decoded.completed)
                try store.save(imported)
                editing = imported
            } catch { errorMessage = error.localizedDescription }
        }
        .studioError($errorMessage)
    }

    private func loadLibrary() {
        do {
            palette = try Palette.load()
            try store.load()
            storageReady = true
        } catch { storageReady = false; errorMessage = error.localizedDescription }
    }

    private func openAfterSheet(_ pattern: Pattern) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            editing = pattern
        }
    }
}

private struct ImageDraft: Identifiable { let id = UUID(); let data: Data }

struct PatternThumbnail: View {
    let pattern: Pattern
    let colors: [String: String]
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let cell = min(size.width / CGFloat(max(1, pattern.width)), size.height / CGFloat(max(1, pattern.height)))
                let origin = CGPoint(x: (size.width - cell * CGFloat(pattern.width)) / 2,
                                     y: (size.height - cell * CGFloat(pattern.height)) / 2)
                for (index, id) in pattern.cells.enumerated() {
                    guard let id, let hex = colors[id] else { continue }
                    let rect = CGRect(x: origin.x + CGFloat(index % pattern.width) * cell,
                                      y: origin.y + CGFloat(index / pattern.width) * cell, width: cell + 0.2, height: cell + 0.2)
                    context.fill(Path(rect), with: .color(Color(beadHex: hex)))
                }
            }
        }
        .accessibilityLabel("\(pattern.width)乘\(pattern.height)格的图纸预览")
    }
}
