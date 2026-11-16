import SwiftUI

/// Transport + keyframe timeline for the selected layer.
/// Drag anywhere on the ruler to scrub; drag a diamond to retime it; tap to select it.
struct TimelineStrip: View {
    @ObservedObject var model: EditorModel
    private let gutter: CGFloat = 34
    private let durations: [Double] = [2, 3, 4, 6, 8, 10, 12, 16, 20]

    var body: some View {
        VStack(spacing: 8) {
            transport
            tracksArea
            if let (prop, kf) = selectedKeyframeInfo { keyframeBar(prop, kf) }
        }
        .padding(12)
        .glassCard(radius: 26)
    }

    // MARK: Transport
    private var transport: some View {
        HStack(spacing: 10) {
            GlassIconButton(systemName: model.isPlaying ? "pause.fill" : "play.fill", size: 38, active: model.isPlaying) { model.togglePlay() }
            TimelineView(.animation(minimumInterval: 1 / 15, paused: !model.isPlaying)) { ctx in
                let t = model.isPlaying ? model.currentTime(at: ctx.date) : model.time
                Text(String(format: "%.2f", t)).font(.system(.title3, design: .monospaced).weight(.semibold))
                    + Text(" / \(Int(model.project.duration))s").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            GlassIconButton(systemName: "record.circle", tint: .red, size: 38, active: model.isRecording) {
                model.isRecording.toggle(); if model.isRecording { model.pause() }
            }
            Menu {
                ForEach(durations, id: \.self) { d in Button("\(Int(d)) seconds") { model.setDuration(d) } }
            } label: {
                Label("\(Int(model.project.duration))s loop", systemImage: "repeat").font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 9).glassCapsule(interactive: true)
            }
        }
    }

    // MARK: Tracks
    private var tracksArea: some View {
        let layer = model.selectedLayer
        let tracks = layer?.tracks.sorted { $0.property.rawValue < $1.property.rawValue } ?? []
        return Group {
            if model.isRecording {
                Label("Record is armed — drag the selected layer; it plays back as a seamless loop.", systemImage: "hand.draw")
                    .font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else if tracks.isEmpty {
                Text(layer == nil ? "Select a layer to animate it." : "No motion yet. Drag the playhead, move the layer and tap ◆, or pick a preset in Motion.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                GeometryReader { g in
                    let w = g.size.width - gutter
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            ruler(width: w)
                            ForEach(tracks) { t in trackRow(t, width: w) }
                        }
                        playhead(width: w, height: g.size.height)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        model.scrub(to: Double((v.location.x - gutter) / max(1, w)) * model.project.duration)
                    })
                }
                .frame(height: 22 + CGFloat(tracks.count) * 30 + 6)
            }
        }
    }

    private func ruler(width w: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08)).frame(height: 18)
                ForEach(0...Int(model.project.duration), id: \.self) { s in
                    Text("\(s)").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                        .position(x: w * CGFloat(Double(s) / model.project.duration), y: 9)
                }
            }.frame(width: w, height: 18)
        }.frame(height: 22)
    }

    private func trackRow(_ t: Track, width w: CGFloat) -> some View {
        HStack(spacing: 0) {
            Image(systemName: t.property.symbol).font(.system(size: 12)).frame(width: gutter).foregroundStyle(Theme.amber)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.05)).frame(height: 26)
                // Span between first and last keyframe
                if let f = t.keyframes.map(\.time).min(), let l = t.keyframes.map(\.time).max(), l > f {
                    Capsule().fill(Theme.amber.opacity(0.22)).frame(width: w * CGFloat((l - f) / model.project.duration), height: 6)
                        .offset(x: w * CGFloat(f / model.project.duration))
                }
                ForEach(t.keyframes) { k in
                    Diamond(selected: model.selectedKeyframe == k.id)
                        .frame(width: 18, height: 18)
                        .position(x: w * CGFloat(k.time / model.project.duration), y: 13)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("track-\(t.property.rawValue)"))
                                .onChanged { v in
                                    if model.selectedKeyframe != k.id { model.beginEdit(); model.selectedKeyframe = k.id; Haptics.select() }
                                    model.moveKeyframe(k.id, in: t.property, to: Double(v.location.x / max(1, w)) * model.project.duration)
                                    model.time = min(max(model.time, 0), model.project.duration)
                                })
                }
            }
            .frame(width: w, height: 26)
            .coordinateSpace(name: "track-\(t.property.rawValue)")
        }.frame(height: 26)
    }

    private func playhead(width w: CGFloat, height h: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !model.isPlaying)) { ctx in
            let t = model.isPlaying ? model.currentTime(at: ctx.date) : model.time
            Capsule().fill(.white).frame(width: 2, height: h)
                .shadow(color: Theme.amber, radius: 4)
                .offset(x: gutter + w * CGFloat(t / model.project.duration) - 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: Selected keyframe
    private var selectedKeyframeInfo: (AnimProperty, Keyframe)? {
        guard let id = model.selectedKeyframe, let l = model.selectedLayer else { return nil }
        for t in l.tracks { if let k = t.keyframes.first(where: { $0.id == id }) { return (t.property, k) } }
        return nil
    }

    private func keyframeBar(_ prop: AnimProperty, _ kf: Keyframe) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Easing.presets, id: \.0) { name, e in
                        Button { model.setEasing(e, for: kf.id, in: prop) } label: {
                            Text(name).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                                .foregroundStyle(kf.easing == e ? .black : .white)
                                .background { if kf.easing == e { Capsule().fill(Theme.accentGradient) } }
                                .glassCapsule()
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button(role: .destructive) { model.deleteKeyframe(kf.id, in: prop) } label: { Image(systemName: "trash").font(.footnote) }
                .buttonStyle(.plain).padding(8).glass(in: Circle())
        }
    }
}

struct Diamond: View {
    var selected: Bool
    var body: some View {
        Rectangle().fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white))
            .rotationEffect(.degrees(45)).scaleEffect(0.62)
            .overlay(Rectangle().stroke(Theme.amber, lineWidth: selected ? 0 : 1.5).rotationEffect(.degrees(45)).scaleEffect(0.62))
            .scaleEffect(selected ? 1.25 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: selected)
    }
}
