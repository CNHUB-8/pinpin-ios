import SwiftUI

struct PatternEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatternStore
    let palette: [BeadColor]
    @State private var pattern: Pattern
    @State private var selectedID: String
    @State private var tool: PaintTool = .brush
    @State private var zoom = 1.0
    @State private var undoStack: [Pattern] = []
    @State private var redoStack: [Pattern] = []
    @State private var strokeStarted = false
    @State private var dirty = false
    @State private var showStats = false
    @State private var showPalette = false
    @State private var errorMessage: String?
    @State private var shareItem: StudioShareItem?
    @State private var showCloseOptions = false
    @State private var showingSaved = false

    init(pattern: Pattern, palette: [BeadColor], store: PatternStore) {
        self.store = store; self.palette = palette
        _pattern = State(initialValue: pattern)
        _selectedID = State(initialValue: palette.first?.id ?? "")
    }
    private var colors: [String: String] { palette.hexByID }
    private var beads: Int { pattern.counts.values.reduce(0, +) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("作品名", text: $pattern.title).font(.headline).textFieldStyle(.roundedBorder)
                    .onChange(of: pattern.title) { _, _ in dirty = true }
                Button { save() } label: { Label("保存", systemImage: "checkmark.circle") }
                    .buttonStyle(.borderedProminent)
            }.padding(.horizontal).padding(.vertical, 10)
            HStack {
                Picker("工具", selection: $tool) {
                    ForEach(PaintTool.allCases) { item in Image(systemName: item.symbol).tag(item) }
                }.pickerStyle(.segmented)
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(undoStack.isEmpty).accessibilityLabel("撤销")
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(redoStack.isEmpty).accessibilityLabel("重做")
            }.padding(.horizontal).padding(.bottom, 8)
            HStack {
                Text(tool.hint).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(pattern.width) × \(pattern.height)").font(.caption.monospacedDigit())
            }.padding(.horizontal).padding(.bottom, 8)
            ScrollView([.horizontal, .vertical]) {
                BeadCanvas(pattern: pattern, colors: colors, cellSize: 18 * zoom,
                           interactive: tool != .pan, edit: paint, endStroke: { strokeStarted = false })
                    .padding(20)
            }.background(Color(uiColor: .secondarySystemBackground))
            HStack(spacing: 12) {
                Button { showPalette = true } label: {
                    HStack { Circle().fill(Color(beadHex: colors[selectedID] ?? "#000000")).frame(width: 25, height: 25)
                        Text(selectedID).font(.caption.monospaced()); Image(systemName: "chevron.up") }
                }.accessibilityLabel("选择颜色，当前 \(selectedID)")
                Spacer()
                Button { showStats = true } label: { Label("\(beads) 颗 · \(pattern.counts.count) 色", systemImage: "checklist") }
                    .font(.caption)
            }.padding(.horizontal).padding(.top, 12)
            HStack { Image(systemName: "minus.magnifyingglass"); Slider(value: $zoom, in: 0.5...3, step: 0.25)
                Text("\(Int(zoom * 100))%").font(.caption.monospacedDigit()).frame(width: 42)
            }.padding(.horizontal).padding(.vertical, 10)
        }
        .navigationTitle("编辑图纸").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("完成") {
                if dirty { showCloseOptions = true } else { dismiss() }
            } }
            ToolbarItem(placement: .topBarTrailing) {
                Menu { Button("分享 PNG 图纸") { sharePNG() }; Button("分享 JSON 源文件") { shareJSON() } }
                    label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .confirmationDialog("保存此次修改？", isPresented: $showCloseOptions, titleVisibility: .visible) {
            Button("保存并关闭") { if save() { dismiss() } }
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .sheet(isPresented: $showPalette) {
            PalettePicker(palette: palette, selection: $selectedID) { tool = .brush; showPalette = false }
        }
        .sheet(isPresented: $showStats) {
            ColorChecklist(pattern: $pattern, colors: colors, willChange: checkpoint, changed: { dirty = true })
        }
        .sheet(item: $shareItem, onDismiss: { StudioShareItem.cleanExpired() }) { item in
            ActivitySheet(items: [item.url])
        }
        .overlay(alignment: .top) {
            if showingSaved { Label("已保存到本机", systemImage: "checkmark.circle.fill")
                .font(.subheadline).padding(12).background(.regularMaterial, in: Capsule()).padding(.top, 8) }
        }
        .studioError($errorMessage)
        .interactiveDismissDisabled(dirty)
    }

    private func checkpoint() {
        undoStack.append(pattern)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    private func paint(_ index: Int) {
        guard pattern.cells.indices.contains(index) else { return }
        if tool == .picker {
            if let id = pattern.cells[index] { selectedID = id; tool = .brush }
            return
        }
        guard tool != .pan else { return }
        let next: String? = tool == .eraser ? nil : selectedID
        guard next != pattern.cells[index] else { return }
        if !strokeStarted { checkpoint(); strokeStarted = true }
        let previous = pattern.cells[index]
        pattern.cells[index] = next
        // Any changed color needs its materials/completion status checked again.
        if let previous { pattern.completed.remove(previous) }
        if let next { pattern.completed.remove(next) }
        pattern.updatedAt = Date(); dirty = true
    }
    private func undo() {
        guard let prior = undoStack.popLast() else { return }
        redoStack.append(pattern); pattern = prior; strokeStarted = false; dirty = true
    }
    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(pattern); pattern = next; strokeStarted = false; dirty = true
    }
    @discardableResult private func save() -> Bool {
        do {
            pattern.updatedAt = Date()
            try store.save(try pattern.validated())
            dirty = false; showingSaved = true
            Task { @MainActor in try? await Task.sleep(for: .seconds(1.5)); showingSaved = false }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    private func shareJSON() {
        do {
            let value = try pattern.validated()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            shareItem = try StudioShareItem(data: encoder.encode(value), filename: "图纸.json")
        } catch { errorMessage = error.localizedDescription }
    }
    private func sharePNG() {
        do {
            shareItem = try StudioShareItem(data: PatternPNG.render(try pattern.validated(), palette: palette), filename: "图纸.png")
        } catch { errorMessage = error.localizedDescription }
    }
}

enum PaintTool: String, CaseIterable, Identifiable {
    case brush, eraser, picker, pan
    var id: String { rawValue }
    var symbol: String { switch self { case .brush: return "paintbrush.pointed"; case .eraser: return "eraser"; case .picker: return "eyedropper"; case .pan: return "hand.draw" } }
    var hint: String { switch self { case .brush: return "拖动画笔填色"; case .eraser: return "拖动擦除格子"; case .picker: return "轻触图纸吸取颜色"; case .pan: return "拖动查看画布，使用下方滑杆缩放" } }
}

private struct BeadCanvas: View {
    let pattern: Pattern
    let colors: [String: String]
    let cellSize: Double
    let interactive: Bool
    let edit: (Int) -> Void
    let endStroke: () -> Void
    @State private var lastIndex: Int?
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for (index, value) in pattern.cells.enumerated() {
                let x = Double(index % pattern.width) * cellSize, y = Double(index / pattern.width) * cellSize
                let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                if let value, let hex = colors[value] {
                    context.fill(Path(rect), with: .color(Color(beadHex: hex)))
                    if cellSize >= 30 {
                        let text = Text(value).font(.system(size: min(9, cellSize / 4))).foregroundColor(Color(beadHex: hex).legibleText)
                        context.draw(text, at: CGPoint(x: x + cellSize / 2, y: y + cellSize / 2))
                    }
                } else if (index % pattern.width + index / pattern.width) % 2 == 0 {
                    context.fill(Path(rect), with: .color(.gray.opacity(0.08)))
                }
                context.stroke(Path(rect), with: .color(.black.opacity(0.15)), lineWidth: 0.5)
            }
        }
        .frame(width: Double(pattern.width) * cellSize, height: Double(pattern.height) * cellSize)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { event in
            let x = Int(floor(event.location.x / cellSize)), y = Int(floor(event.location.y / cellSize))
            guard x >= 0, y >= 0, x < pattern.width, y < pattern.height else { return }
            let index = y * pattern.width + x
            guard lastIndex != index else { return }
            lastIndex = index; edit(index)
        }.onEnded { _ in lastIndex = nil; endStroke() }, including: interactive ? .all : .none)
        .accessibilityLabel("可编辑拼豆画布，\(pattern.width)乘\(pattern.height)格")
    }
}

private struct PalettePicker: View {
    @Environment(\.dismiss) private var dismiss
    let palette: [BeadColor]
    @Binding var selection: String
    let choose: () -> Void
    @State private var query = ""
    private var filtered: [BeadColor] { query.isEmpty ? palette : palette.filter { $0.id.localizedCaseInsensitiveContains(query) || $0.hex.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 62))], spacing: 14) {
                ForEach(filtered) { color in
                    Button { selection = color.id; choose() } label: {
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 9).fill(Color(beadHex: color.hex)).frame(height: 42)
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(selection == color.id ? .indigo : .gray.opacity(0.2), lineWidth: selection == color.id ? 3 : 1))
                            Text(color.id).font(.caption.monospaced()).foregroundStyle(.primary)
                        }
                    }.accessibilityLabel("色号 \(color.id)")
                }
            }.padding() }
            .searchable(text: $query, prompt: "搜索色号或 HEX")
            .navigationTitle("选择颜色").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct ColorChecklist: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var pattern: Pattern
    let colors: [String: String]
    let willChange: () -> Void
    let changed: () -> Void
    private struct Entry: Identifiable { let id: String; let count: Int }
    private var entries: [Entry] { pattern.counts.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }.map { Entry(id: $0.key, count: $0.value) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("共 \(entries.reduce(0) { $0 + $1.count }) 颗，\(entries.count) 种颜色")
                    Text("完成某一种颜色后勾选；修改该颜色的格子会清除勾选。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(entries) { item in
                    let id = item.id
                    let count = item.count
                    Toggle(isOn: Binding(get: { pattern.completed.contains(id) }, set: { checked in
                        willChange()
                        if checked { pattern.completed.insert(id) } else { pattern.completed.remove(id) }
                        pattern.updatedAt = Date(); changed()
                    })) {
                        HStack { Circle().fill(Color(beadHex: colors[id] ?? "#000000")).frame(width: 26, height: 26)
                            Text(id).font(.body.monospaced()); Spacer(); Text("\(count) 颗").foregroundStyle(.secondary) }
                    }
                }
            }.navigationTitle("按色备料与进度").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
