import SwiftUI
import PhotosUI

enum DockTab: String, CaseIterable, Identifiable {
    case layers, motion, adjust, canvas
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .layers: return "square.3.layers.3d"; case .motion: return "wand.and.rays"; case .adjust: return "slider.horizontal.3"; case .canvas: return "iphone.gen3" }
    }
}

struct ToolDock: View {
    @ObservedObject var model: EditorModel
    @Binding var tab: DockTab
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(DockTab.allCases) { t in
                    Button { Haptics.select(); withAnimation(.snappy) { tab = t } } label: {
                        VStack(spacing: 2) { Image(systemName: t.symbol).font(.system(size: 17, weight: .semibold)); Text(t.title).font(.system(size: 10, weight: .semibold)) }
                            .foregroundStyle(tab == t ? .black : .white.opacity(0.8))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background { if tab == t { Capsule().fill(Theme.accentGradient) } }
                    }.buttonStyle(.plain)
                }
            }.padding(4).glassCapsule()
            Group {
                switch tab {
                case .layers: LayersPanel(model: model)
                case .motion: MotionPanel(model: model)
                case .adjust: AdjustPanel(model: model)
                case .canvas: CanvasPanel(model: model)
                }
            }.frame(height: 150).transition(.opacity)
        }
    }
}

// MARK: Layers
struct LayersPanel: View {
    @ObservedObject var model: EditorModel
    @State private var photo: PhotosPickerItem?
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                PhotosPicker(selection: $photo, matching: .images) { pill("photo", "Photo") }.buttonStyle(.plain)
                Button { model.addShape(.rectangle) } label: { pill("rectangle.fill", "Rect") }.buttonStyle(.plain)
                Button { model.addShape(.ellipse) } label: { pill("circle.fill", "Circle") }.buttonStyle(.plain)
                Spacer()
                if model.selectedLayer != nil {
                    iconBtn("arrow.up") { model.moveSelected(up: true) }
                    iconBtn("arrow.down") { model.moveSelected(up: false) }
                    iconBtn("plus.square.on.square") { model.duplicateSelected() }
                    iconBtn("trash") { model.deleteSelected() }
                }
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.drawOrder.reversed()) { l in row(l) }
                    if model.project.layers.isEmpty { Text("Add a photo or shape to begin.").font(.caption).foregroundStyle(.secondary).padding(.top, 20) }
                }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { model.addImage(img) }
                photo = nil
            }
        }
    }
    private func pill(_ i: String, _ t: String) -> some View {
        Label(t, systemImage: i).font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8).glassCapsule(interactive: true)
    }
    private func iconBtn(_ i: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: i).font(.footnote.weight(.semibold)).frame(width: 32, height: 32).glass(in: Circle(), interactive: true) }.buttonStyle(.plain)
    }
    private func row(_ l: WallpaperLayer) -> some View {
        let on = model.selection == l.id
        return HStack(spacing: 10) {
            Image(systemName: l.kind == .image ? "photo" : l.kind == .ellipse ? "circle.fill" : "rectangle.fill")
                .foregroundStyle(l.kind == .image ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Color(l.fill))).frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(l.name).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(l.plane.title + (l.tracks.isEmpty ? "" : " • \(l.tracks.count) motion")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { toggle(l) { $0.isLocked.toggle() } } label: { Image(systemName: l.isLocked ? "lock.fill" : "lock.open").font(.caption) }.buttonStyle(.plain).opacity(l.isLocked ? 1 : 0.4)
            Button { toggle(l) { $0.isHidden.toggle() } } label: { Image(systemName: l.isHidden ? "eye.slash" : "eye").font(.caption) }.buttonStyle(.plain).opacity(l.isHidden ? 0.5 : 1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Theme.amber.opacity(0.22) : .white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Theme.amber.opacity(0.7) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { Haptics.select(); model.selection = l.id }
    }
    private func toggle(_ l: WallpaperLayer, _ f: (inout WallpaperLayer) -> Void) {
        let old = model.selection; model.selection = l.id; model.beginEdit(); model.mutateSelected(f); model.selection = old
        Haptics.tap()
    }
}

// MARK: Motion
struct MotionPanel: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MotionPreset.allCases) { p in
                        Button { model.applyPreset(p) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: p.symbol).font(.title3).foregroundStyle(Theme.amber)
                                Text(p.title).font(.caption.weight(.semibold))
                            }.frame(width: 72, height: 62).glass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                        }.buttonStyle(PressScale()).disabled(model.selectedLayer == nil)
                    }
                }
            }
            HStack(spacing: 6) {
                SectionTitle("Keyframe at playhead")
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(AnimProperty.allCases) { p in
                    let has = model.hasKeyframe(p)
                    Button { model.toggleKeyframe(p) } label: {
                        HStack(spacing: 4) { Image(systemName: has ? "diamond.fill" : "diamond").font(.caption2); Text(p.title).font(.caption.weight(.semibold)) }
                            .foregroundStyle(has ? .black : .white).padding(.horizontal, 10).padding(.vertical, 8)
                            .background { if has { Capsule().fill(Theme.accentGradient) } }.glassCapsule(interactive: true)
                    }.buttonStyle(.plain).disabled(model.selectedLayer == nil)
                }
            }
            if let l = model.selectedLayer, !l.tracks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(l.tracks) { t in
                            Menu {
                                Picker("Loop", selection: Binding(get: { t.loop }, set: { model.setLoop(t.property, $0) })) {
                                    ForEach(LoopMode.allCases) { Text($0.title).tag($0) }
                                }
                                Button("Close loop (return to start)") { model.closeLoop(t.property) }
                                Button("Remove \(t.property.title) motion", role: .destructive) { model.removeTrack(t.property) }
                            } label: {
                                Label("\(t.property.title) • \(t.loop.title)", systemImage: t.property.symbol).font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6).glassCapsule()
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Adjust
struct AdjustPanel: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        if let l = model.selectedLayer {
            let s = model.state(l)
            ScrollView {
                VStack(spacing: 10) {
                    slider("Rotation", "rotate.right", s.rotation, -180...180, "%.0f°", .rotation)
                    slider("Scale", "arrow.up.left.and.arrow.down.right", s.scale, 0.1...4, "%.2f×", .scale)
                    slider("Opacity", "circle.lefthalf.filled", s.opacity, 0...1, "%.0f%%", .opacity, pct: true)
                    HStack {
                        Picker("Depth", selection: Binding(get: { l.plane }, set: { v in model.beginEdit(); model.mutateSelected { $0.plane = v } })) {
                            ForEach(Plane.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    if l.kind != .image {
                        ColorPicker("Fill", selection: Binding(get: { Color(l.fill) }, set: { c in
                            let u = UIColor(c); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; u.getRed(&r, green: &g, blue: &b, alpha: &a)
                            model.mutateSelected { $0.fill = RGBA(Double(r), Double(g), Double(b), Double(a)) } }), supportsOpacity: true)
                            .font(.footnote.weight(.semibold))
                        if l.kind == .rectangle {
                            HStack { Text("Corners").font(.footnote.weight(.semibold)); Slider(value: Binding(get: { l.cornerRadius }, set: { v in model.mutateSelected { $0.cornerRadius = v } }), in: 0...200) { e in if e { model.beginEdit() } } }
                        }
                    }
                    Text("Depth: Background sits behind the clock, Floating and Foreground are separate layers in the exported file.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        } else {
            Text("Select a layer to adjust it.").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func slider(_ t: String, _ icon: String, _ v: Double, _ r: ClosedRange<Double>, _ fmt: String, _ p: AnimProperty, pct: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(Theme.amber)
            Slider(value: Binding(get: { v }, set: { model.setValue(p, [$0]) }), in: r) { editing in if editing { model.beginEdit() } }
            Text(String(format: fmt, pct ? v * 100 : v)).font(.system(.caption, design: .monospaced)).frame(width: 52, alignment: .trailing)
            Button { model.toggleKeyframe(p) } label: { Image(systemName: model.hasKeyframe(p) ? "diamond.fill" : "diamond").foregroundStyle(Theme.amber) }.buttonStyle(.plain)
        }
    }
}

// MARK: Canvas
struct CanvasPanel: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Text("Name").font(.footnote.weight(.semibold))
                    TextField("Untitled", text: Binding(get: { model.project.name }, set: { model.project.name = $0 })).textFieldStyle(.roundedBorder)
                }
                ColorPicker("Background colour", selection: Binding(get: { Color(model.project.background) }, set: { c in
                    let u = UIColor(c); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; u.getRed(&r, green: &g, blue: &b, alpha: &a)
                    model.project.background = RGBA(Double(r), Double(g), Double(b)) }), supportsOpacity: false).font(.footnote.weight(.semibold))
                HStack {
                    Text("Canvas").font(.footnote.weight(.semibold)); Spacer()
                    Menu {
                        ForEach(DevicePreset.all) { d in Button("\(d.name) — \(Int(d.width))×\(Int(d.height))") { resize(d) } }
                    } label: { Text("\(Int(model.project.canvasWidth))×\(Int(model.project.canvasHeight))").font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 6).glassCapsule(interactive: true) }
                }
                Toggle("Lock screen guide", isOn: $model.showLockGuide).font(.footnote.weight(.semibold)).tint(Theme.amber)
            }
        }
    }
    private func resize(_ d: DevicePreset) {
        model.beginEdit()
        let sx = d.width / model.project.canvasWidth, sy = d.height / model.project.canvasHeight
        for i in model.project.layers.indices {
            model.project.layers[i].position = CGPoint(x: model.project.layers[i].position.x * sx, y: model.project.layers[i].position.y * sy)
            for ti in model.project.layers[i].tracks.indices where model.project.layers[i].tracks[ti].property == .position {
                for ki in model.project.layers[i].tracks[ti].keyframes.indices {
                    let v = model.project.layers[i].tracks[ti].keyframes[ki].value
                    model.project.layers[i].tracks[ti].keyframes[ki].value = [v[0] * sx, v[1] * sy]
                }
            }
        }
        model.project.canvasWidth = d.width; model.project.canvasHeight = d.height; Haptics.select()
    }
}
