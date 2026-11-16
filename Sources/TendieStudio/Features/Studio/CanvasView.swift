import SwiftUI

/// The live canvas: a real Core Animation preview with a SwiftUI edit layer on top.
/// Drag = move, pinch = scale, twist = rotate. Edits write keyframes when the
/// property is animated, otherwise they change the base value.
struct CanvasView: View {
    @ObservedObject var model: EditorModel
    private enum Mode { case idle, ignore, move(CGPoint), record(CGPoint) }
    @State private var mode: Mode = .idle
    @State private var pinchBase: Double?
    @State private var twistBase: Double?

    var body: some View {
        GeometryReader { geo in
            let cw = model.project.canvasWidth, ch = model.project.canvasHeight
            let k = max(0.05, min((geo.size.width - 16) / cw, (geo.size.height - 12) / ch))
            ZStack {
                canvas(k: k, cw: cw, ch: ch)
                    .frame(width: cw * k, height: ch * k)
                    .clipShape(RoundedRectangle(cornerRadius: 46 * k * (cw / 393), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 46 * k * (cw / 393), style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(k: k, cw: cw, ch: ch))
                    .simultaneousGesture(magnify)
                    .simultaneousGesture(twist)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func canvas(k: CGFloat, cw: Double, ch: Double) -> some View {
        ZStack {
            WallpaperPreview(project: model.project, assetsDir: model.assetsDir, time: model.time, playing: model.isPlaying)
            if model.showLockGuide { LockGuide(k: k * (cw / 393)) }
            if !model.isPlaying {
                if model.snapX { Rectangle().fill(Theme.amber).frame(width: 1).frame(maxHeight: .infinity).allowsHitTesting(false) }
                if model.snapY { Rectangle().fill(Theme.amber).frame(height: 1).frame(maxWidth: .infinity).allowsHitTesting(false) }
                if let l = model.selectedLayer { SelectionBox(layer: l, state: model.state(l), k: k, recording: model.isRecording)
                    .frame(width: cw * k, height: ch * k, alignment: .topLeading) }
            }
        }
    }

    // MARK: Gestures
    private func dragGesture(k: CGFloat, cw: Double, ch: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let start = CGPoint(x: v.startLocation.x / k, y: v.startLocation.y / k)
                if case .idle = mode {
                    if model.isPlaying { mode = .ignore; return }
                    if let hit = model.hitTest(start), model.selection != hit { model.selection = hit; Haptics.select() }
                    guard let l = model.selectedLayer, !l.isLocked, model.hitTest(start) == l.id else { mode = .ignore; return }
                    let s = model.state(l)
                    if model.isRecording { model.recordBegan(layer: l.id, at: s.position); mode = .record(s.position) }
                    else { model.beginEdit(); mode = .move(s.position) }
                }
                switch mode {
                case .move(let p0):
                    var x = p0.x + v.translation.width / k, y = p0.y + v.translation.height / k
                    let sx = abs(x - cw / 2) < 6, sy = abs(y - ch / 2) < 6
                    if sx { x = cw / 2 }; if sy { y = ch / 2 }
                    if (sx && !model.snapX) || (sy && !model.snapY) { Haptics.select() }
                    model.snapX = sx; model.snapY = sy
                    model.setValue(.position, [x, y])
                case .record(let p0):
                    if model.isRecordingTake {
                        model.recordMoved(CGPoint(x: min(max(p0.x + v.translation.width / k, 0), cw),
                                                  y: min(max(p0.y + v.translation.height / k, 0), ch)))
                    }
                default: break
                }
            }
            .onEnded { v in
                let moved = hypot(v.translation.width, v.translation.height) > 4
                switch mode {
                case .ignore:
                    if !moved { if model.isPlaying { model.pause() } else if model.selection != nil && model.hitTest(CGPoint(x: v.startLocation.x / k, y: v.startLocation.y / k)) == nil { model.selection = nil } }
                case .record: model.recordEnded()
                default: break
                }
                mode = .idle; model.snapX = false; model.snapY = false
            }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                guard !model.isPlaying, let l = model.selectedLayer, !l.isLocked else { return }
                if pinchBase == nil { model.beginEdit(); pinchBase = model.state(l).scale }
                model.setValue(.scale, [min(max((pinchBase ?? 1) * v.magnification, 0.05), 20)])
            }
            .onEnded { _ in pinchBase = nil }
    }

    private var twist: some Gesture {
        RotateGesture()
            .onChanged { v in
                guard !model.isPlaying, let l = model.selectedLayer, !l.isLocked else { return }
                if twistBase == nil { model.beginEdit(); twistBase = model.state(l).rotation }
                var r = (twistBase ?? 0) + v.rotation.degrees
                // Soft snap to 15° steps.
                let step = (r / 15).rounded() * 15
                if abs(r - step) < 3 { if abs(r - step) > 0.01 && abs(step - (model.state(l).rotation)) > 0.5 { Haptics.select() }; r = step }
                model.setValue(.rotation, [r])
            }
            .onEnded { _ in twistBase = nil }
    }
}

struct SelectionBox: View {
    let layer: WallpaperLayer
    let state: AnimationBaker.State
    let k: CGFloat
    let recording: Bool
    var body: some View {
        let w = layer.size.width * state.scale * k, h = layer.size.height * state.scale * k
        ZStack {
            RoundedRectangle(cornerRadius: 3).strokeBorder(recording ? Color.red : Theme.amber, style: StrokeStyle(lineWidth: 1.5, dash: layer.isLocked ? [4, 3] : []))
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(.white).frame(width: 9, height: 9).overlay(Circle().stroke(recording ? Color.red : Theme.amber, lineWidth: 1.5))
                    .position(x: i % 2 == 0 ? 0 : w, y: i < 2 ? 0 : h)
            }
        }
        .frame(width: w, height: h)
        .rotationEffect(.degrees(state.rotation))
        .position(x: state.position.x * k, y: state.position.y * k)
        .allowsHitTesting(false)
    }
}

/// Faint stand-in for the lock screen clock and controls, so you can see what
/// the system will draw over your wallpaper. Purely a visual aid; never exported.
struct LockGuide: View {
    let k: CGFloat
    var body: some View {
        GeometryReader { g in
            ZStack {
                VStack(spacing: 0) {
                    Text("Monday 15 November").font(.system(size: 20 * k, weight: .semibold))
                    Text("9:41").font(.system(size: 96 * k, weight: .semibold, design: .rounded))
                }.position(x: g.size.width / 2, y: 150 * k)
                HStack {
                    Circle().frame(width: 50 * k, height: 50 * k)
                    Spacer()
                    Circle().frame(width: 50 * k, height: 50 * k)
                }.padding(.horizontal, 44 * k).position(x: g.size.width / 2, y: g.size.height - 70 * k)
            }
            .foregroundStyle(.white.opacity(0.32)).allowsHitTesting(false)
        }.allowsHitTesting(false)
    }
}
