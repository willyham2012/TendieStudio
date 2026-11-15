import SwiftUI
import UIKit

/// All editor state and editing rules. Views stay thin.
@MainActor
final class EditorModel: ObservableObject {
    private let store: ProjectStore
    let assetsDir: URL

    @Published var project: WallpaperProject { didSet { if project != oldValue { scheduleSave() } } }
    @Published var selection: UUID?
    @Published var selectedKeyframe: UUID?
    @Published var time: Double = 0
    @Published private(set) var isPlaying = false
    @Published var isRecording = false
    @Published var showLockGuide = true
    @Published var snapX = false
    @Published var snapY = false
    @Published private(set) var undoDepth = 0
    @Published private(set) var redoDepth = 0
    @Published var saveError: String?

    private var undoStack: [WallpaperProject] = []
    private var redoStack: [WallpaperProject] = []
    private var saveTask: Task<Void, Never>?
    private var playStart: (date: Date, offset: Double)?
    private var recording: (start: Date, samples: [(t: Double, p: CGPoint)], layer: UUID)?

    init(store: ProjectStore, id: UUID) throws {
        self.store = store
        self.project = try store.load(id)
        self.assetsDir = store.assetsDir(id)
        self.selection = project.layers.last?.id
    }

    // MARK: Lookup
    func index(of id: UUID?) -> Int? { id.flatMap { i in project.layers.firstIndex { $0.id == i } } }
    var selectedLayer: WallpaperLayer? { index(of: selection).map { project.layers[$0] } }
    var selectedTime: Double { time }

    /// Layers in draw order (bottom → top) across planes.
    var drawOrder: [WallpaperLayer] { Plane.allCases.flatMap { p in project.layers.filter { $0.plane == p } } }

    func state(_ l: WallpaperLayer) -> AnimationBaker.State { AnimationBaker.state(of: l, at: time) }

    func hitTest(_ p: CGPoint) -> UUID? {
        for l in drawOrder.reversed() where !l.isHidden && !l.isLocked {
            let s = state(l)
            let dx = p.x - s.position.x, dy = p.y - s.position.y
            let a = -s.rotation * .pi / 180
            let lx = dx * cos(a) - dy * sin(a), ly = dx * sin(a) + dy * cos(a)
            if abs(lx) <= l.size.width * s.scale / 2, abs(ly) <= l.size.height * s.scale / 2 { return l.id }
        }
        return nil
    }

    // MARK: Undo / redo
    func beginEdit() {
        if undoStack.last != project { undoStack.append(project) }
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll(); syncDepths()
    }
    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(project); project = prev; fixSelection(); syncDepths(); Haptics.tap()
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project); project = next; fixSelection(); syncDepths(); Haptics.tap()
    }
    private func syncDepths() { undoDepth = undoStack.count; redoDepth = redoStack.count }
    private func fixSelection() { if index(of: selection) == nil { selection = project.layers.last?.id } }

    // MARK: Layers
    func addImage(_ image: UIImage) {
        do {
            let a = try store.addImage(image, to: project.id)
            beginEdit()
            var l = WallpaperLayer.image(name: "Image \(project.layers.count + 1)", assetName: a.name, pixelSize: a.size,
                                         canvas: project.canvasSize, cover: project.layers.isEmpty)
            l.plane = .floating
            project.layers.append(l); selection = l.id; Haptics.success()
        } catch { saveError = error.localizedDescription }
    }

    func addShape(_ kind: LayerKind) {
        beginEdit()
        let side = min(project.canvasWidth, project.canvasHeight) * 0.35
        var l = WallpaperLayer(name: kind == .ellipse ? "Circle" : "Rectangle", kind: kind, assetName: nil,
                               position: CGPoint(x: project.canvasWidth / 2, y: project.canvasHeight / 2),
                               size: CGSize(width: side, height: side))
        l.fill = [RGBA(1, 0.69, 0.2), RGBA(1, 0.42, 0.3), RGBA(0.4, 0.5, 1), RGBA(0.3, 0.85, 0.7)].randomElement()!
        if kind == .rectangle { l.cornerRadius = 28 }
        project.layers.append(l); selection = l.id; Haptics.tap()
    }

    func deleteSelected() {
        guard let i = index(of: selection) else { return }
        beginEdit(); project.layers.remove(at: i)
        selection = project.layers.indices.contains(i - 1) ? project.layers[i - 1].id : project.layers.last?.id
        Haptics.warning()
    }

    func duplicateSelected() {
        guard let i = index(of: selection) else { return }
        beginEdit()
        var c = project.layers[i]; c.id = UUID(); c.name += " copy"
        c.position.x += 24; c.position.y += 24
        c.tracks = c.tracks.map { t in
            var t = t; t.id = UUID()
            t.keyframes = t.keyframes.map { var k = $0; k.id = UUID(); if t.property == .position { k.value = [k.value[0] + 24, k.value[1] + 24] }; return k }
            return t
        }
        project.layers.insert(c, at: i + 1); selection = c.id; Haptics.tap()
    }

    func moveSelected(up: Bool) {
        guard let i = index(of: selection) else { return }
        let j = up ? i + 1 : i - 1
        guard project.layers.indices.contains(j) else { return }
        beginEdit(); project.layers.swapAt(i, j); Haptics.select()
    }

    func mutateSelected(_ f: (inout WallpaperLayer) -> Void) {
        guard let i = index(of: selection) else { return }
        f(&project.layers[i])
    }

    // MARK: Values (static or keyframed)
    /// Sets a property. If it has a track, writes a keyframe at the playhead;
    /// otherwise changes the layer's base value.
    func setValue(_ prop: AnimProperty, _ v: [Double]) {
        guard let i = index(of: selection), !isRecording || prop != .position else { return }
        if let ti = project.layers[i].tracks.firstIndex(where: { $0.property == prop }) {
            AnimationBaker.upsert(&project.layers[i].tracks[ti], time: time, value: v)
            selectedKeyframe = project.layers[i].tracks[ti].keyframes.first { abs($0.time - time) < 0.02 }?.id
        } else {
            switch prop {
            case .position: project.layers[i].position = CGPoint(x: v[0], y: v[1])
            case .rotation: project.layers[i].rotation = v[0]
            case .scale: project.layers[i].scale = v[0]
            case .opacity: project.layers[i].opacity = v[0]
            }
        }
    }

    func hasKeyframe(_ prop: AnimProperty) -> Bool {
        selectedLayer?.track(prop)?.keyframes.contains { abs($0.time - time) < 0.02 } ?? false
    }

    /// The ◆ button: add/remove a keyframe for `prop` at the playhead.
    func toggleKeyframe(_ prop: AnimProperty) {
        guard let i = index(of: selection) else { return }
        beginEdit()
        let l = project.layers[i]
        let cur = AnimationBaker.state(of: l, at: time)
        let value: [Double]
        switch prop {
        case .position: value = [cur.position.x, cur.position.y]
        case .rotation: value = [cur.rotation]
        case .scale: value = [cur.scale]
        case .opacity: value = [cur.opacity]
        }
        if let ti = l.tracks.firstIndex(where: { $0.property == prop }) {
            if let ki = l.tracks[ti].keyframes.firstIndex(where: { abs($0.time - time) < 0.02 }) {
                project.layers[i].tracks[ti].keyframes.remove(at: ki)
                if project.layers[i].tracks[ti].keyframes.isEmpty { project.layers[i].tracks.remove(at: ti) }
                Haptics.tap()
            } else {
                AnimationBaker.upsert(&project.layers[i].tracks[ti], time: time, value: value)
                Haptics.medium()
            }
        } else {
            var t = Track(property: prop, keyframes: [])
            if time > 0.05 { AnimationBaker.upsert(&t, time: 0, value: value) }   // motion starts from where it is now
            AnimationBaker.upsert(&t, time: time, value: value)
            project.layers[i].tracks.append(t); Haptics.medium()
        }
    }

    func removeTrack(_ prop: AnimProperty) {
        guard let i = index(of: selection) else { return }
        beginEdit(); project.layers[i].tracks.removeAll { $0.property == prop }
    }

    /// Makes the loop seamless: last keyframe returns to the first keyframe's value at the end of the loop.
    func closeLoop(_ prop: AnimProperty) {
        guard let i = index(of: selection), let ti = project.layers[i].tracks.firstIndex(where: { $0.property == prop }),
              let first = project.layers[i].tracks[ti].keyframes.sorted(by: { $0.time < $1.time }).first else { return }
        beginEdit()
        AnimationBaker.upsert(&project.layers[i].tracks[ti], time: project.duration, value: first.value)
        Haptics.success()
    }

    func setLoop(_ prop: AnimProperty, _ m: LoopMode) {
        guard let i = index(of: selection), let ti = project.layers[i].tracks.firstIndex(where: { $0.property == prop }) else { return }
        beginEdit(); project.layers[i].tracks[ti].loop = m
    }

    func setEasing(_ e: Easing, for kf: UUID, in prop: AnimProperty) {
        guard let i = index(of: selection), let ti = project.layers[i].tracks.firstIndex(where: { $0.property == prop }),
              let ki = project.layers[i].tracks[ti].keyframes.firstIndex(where: { $0.id == kf }) else { return }
        beginEdit(); project.layers[i].tracks[ti].keyframes[ki].easing = e; Haptics.select()
    }

    func moveKeyframe(_ kf: UUID, in prop: AnimProperty, to t: Double) {
        guard let i = index(of: selection), let ti = project.layers[i].tracks.firstIndex(where: { $0.property == prop }),
              let ki = project.layers[i].tracks[ti].keyframes.firstIndex(where: { $0.id == kf }) else { return }
        let snapped = (min(max(t, 0), project.duration) * AnimationBaker.samplesPerSecond).rounded() / AnimationBaker.samplesPerSecond
        project.layers[i].tracks[ti].keyframes[ki].time = snapped
        project.layers[i].tracks[ti].keyframes.sort { $0.time < $1.time }
    }

    func deleteKeyframe(_ kf: UUID, in prop: AnimProperty) {
        guard let i = index(of: selection), let ti = project.layers[i].tracks.firstIndex(where: { $0.property == prop }) else { return }
        beginEdit()
        project.layers[i].tracks[ti].keyframes.removeAll { $0.id == kf }
        if project.layers[i].tracks[ti].keyframes.isEmpty { project.layers[i].tracks.remove(at: ti) }
        selectedKeyframe = nil; Haptics.tap()
    }

    func applyPreset(_ p: MotionPreset) {
        guard let l = selectedLayer, let i = index(of: selection) else { return }
        beginEdit()
        for t in p.tracks(for: l, duration: project.duration) {
            project.layers[i].tracks.removeAll { $0.property == t.property }
            project.layers[i].tracks.append(t)
        }
        time = 0; Haptics.success()
    }

    /// Rescales keyframe times so motion keeps its shape when the loop length changes.
    func setDuration(_ d: Double) {
        guard d != project.duration, d > 0 else { return }
        beginEdit()
        let k = d / project.duration
        for li in project.layers.indices { for ti in project.layers[li].tracks.indices {
            for ki in project.layers[li].tracks[ti].keyframes.indices { project.layers[li].tracks[ti].keyframes[ki].time *= k }
        } }
        project.duration = d; time = min(time, d); Haptics.select()
    }

    // MARK: Playback
    func togglePlay() { isPlaying ? pause() : play() }
    func play() {
        guard !isPlaying else { return }
        isRecording = false
        playStart = (Date(), time); isPlaying = true; Haptics.tap()
    }
    func pause() {
        guard isPlaying else { return }
        time = currentTime(); isPlaying = false; playStart = nil
    }
    func currentTime(at date: Date = Date()) -> Double {
        guard isPlaying, let s = playStart else { return time }
        return (s.offset + date.timeIntervalSince(s.date)).truncatingRemainder(dividingBy: max(0.1, project.duration))
    }
    func scrub(to t: Double) {
        if isPlaying { pause() }
        let c = min(max(t, 0), project.duration)
        if abs(c - time) > 0.001 { time = c }
    }

    // MARK: Motion recording ("drag it around")
    func recordBegan(layer id: UUID, at p: CGPoint) {
        guard let i = index(of: id) else { return }
        beginEdit()
        project.layers[i].tracks.removeAll { $0.property == .position }
        project.layers[i].position = p
        time = 0; recording = (Date(), [(0, p)], id); Haptics.medium()
    }
    func recordMoved(_ p: CGPoint) {
        guard let r = recording, let i = index(of: r.layer) else { return }
        let t = Date().timeIntervalSince(r.start)
        project.layers[i].position = p
        if t - (r.samples.last?.t ?? 0) >= 0.1 { recording?.samples.append((t, p)) }
        if t >= project.duration { recordEnded(final: p) } else { time = t }
    }
    func recordEnded(final: CGPoint? = nil) {
        guard let r = recording, let i = index(of: r.layer) else { return }
        recording = nil
        var samples = r.samples
        let end = Date().timeIntervalSince(r.start)
        if let f = final ?? (samples.last?.p), end > (samples.last?.t ?? 0) { samples.append((min(end, project.duration), f)) }
        guard samples.count >= 2 else { project.layers[i].tracks.removeAll { $0.property == .position }; return }
        var ks = samples.map { Keyframe(time: min($0.t, project.duration), value: [$0.p.x, $0.p.y], easing: .linear) }
        // Return to the start so the wallpaper loops seamlessly.
        let start = ks[0]
        if (ks.last!.time) < project.duration { ks.append(Keyframe(time: project.duration, value: start.value, easing: .linear)) }
        else { ks[ks.count - 1].value = start.value }
        // Quantise to the baker's 1/30 s grid and drop duplicates.
        var track = Track(property: .position, keyframes: [])
        for k in ks { AnimationBaker.upsert(&track, time: k.time, value: k.value, easing: .linear) }
        if track.keyframes.count >= 2 { track.keyframes[track.keyframes.count - 2].easing = .easeInOut }
        project.layers[i].tracks.removeAll { $0.property == .position }
        project.layers[i].tracks.append(track)
        project.layers[i].position = CGPoint(x: start.value[0], y: start.value[1])
        time = 0; Haptics.success()
    }
    var isRecordingTake: Bool { recording != nil }

    // MARK: Persistence
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow(withThumbnail: Bool = false) {
        saveTask?.cancel()
        do {
            let thumb = withThumbnail ? WallpaperRenderer.thumbnail(project, assetsDir: assetsDir) : nil
            try store.save(project, thumbnail: thumb)
        } catch { saveError = error.localizedDescription }
    }
}
