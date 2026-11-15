import SwiftUI

/// Owns the EditorModel for the lifetime of the editor so it is created exactly once.
@MainActor
private final class EditorHolder: ObservableObject {
    let model: EditorModel?
    init(store: ProjectStore, id: UUID) { model = try? EditorModel(store: store, id: id) }
}

struct EditorView: View {
    @EnvironmentObject var app: AppModel
    @StateObject private var holder: EditorHolder
    init(projectID: UUID, store: ProjectStore) { _holder = StateObject(wrappedValue: EditorHolder(store: store, id: projectID)) }
    var body: some View {
        if let model = holder.model { EditorContent(model: model) }
        else {
            // Never crash on a damaged project: tell the user and offer a way out.
            ZStack {
                AuroraBackground()
                ContentUnavailableView {
                    Label("Couldn’t open project", systemImage: "exclamationmark.triangle")
                } description: { Text("The project file is missing or damaged.") } actions: {
                    Button("Close") { app.editingProjectID = nil }.buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }
}

private struct EditorContent: View {
    @ObservedObject var model: EditorModel
    @EnvironmentObject var app: AppModel
    @Environment(\.scenePhase) private var phase
    @State private var tab: DockTab = .layers
    @State private var showExport = false
    @State private var confirmClose = false

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 10) {
                topBar
                CanvasView(model: model).frame(minHeight: 260)
                TimelineStrip(model: model)
                ToolDock(model: model, tab: $tab)
            }
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
        .onChange(of: phase) { _, p in if p != .active { model.saveNow(withThumbnail: true) } }
        .sheet(isPresented: $showExport) { ExportSheet(projectID: model.project.id) }
        .alert("Couldn’t save", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.saveError ?? "") }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            GlassIconButton(systemName: "chevron.down") { model.pause(); model.saveNow(withThumbnail: true); app.editingProjectID = nil }
            VStack(alignment: .leading, spacing: 0) {
                Text(model.project.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("Autosaved • \(Int(model.project.canvasWidth))×\(Int(model.project.canvasHeight))").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            GlassIconButton(systemName: "arrow.uturn.backward", size: 36) { model.undo() }.opacity(model.undoDepth > 0 ? 1 : 0.35).disabled(model.undoDepth == 0)
            GlassIconButton(systemName: "arrow.uturn.forward", size: 36) { model.redo() }.opacity(model.redoDepth > 0 ? 1 : 0.35).disabled(model.redoDepth == 0)
            Button { model.pause(); model.saveNow(withThumbnail: true); Haptics.tap(); showExport = true } label: {
                Label("Export", systemImage: "square.and.arrow.up").font(.subheadline.weight(.bold)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 10).background(Theme.accentGradient, in: Capsule())
            }.buttonStyle(PressScale())
        }.padding(.top, 4)
    }
}

struct ExportSheet: View {
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    @State private var result: ExportResult?
    @State private var fileURL: URL?
    @State private var error: String?
    @State private var working = true

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if working { HStack { ProgressView(); Text("Building and validating…") } }
                        if let r = result {
                            ReportView(report: r.report, warnings: r.warnings).padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                            Text("\(r.fileName) • \(ByteCountFormatter.string(fromByteCount: Int64(r.data.count), countStyle: .file))")
                                .font(.footnote).foregroundStyle(.secondary)
                            if let fileURL {
                                ShareLink(item: fileURL, preview: SharePreview(r.fileName)) {
                                    Label("Share or save .tendies", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                                }.buttonStyle(PrimaryButtonStyle())
                            }
                            Text("Send the file to a tool that can apply .tendies (e.g. Nugget or Pocket Poster) from the share sheet. TendieStudio itself can’t set your Lock Screen — see Library › ? for details.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout) }
                    }.padding(20)
                }
            }
            .navigationTitle("Export").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { await build() }
        }.presentationDetents([.medium, .large])
    }

    private func build() async {
        do {
            let p = try store.load(projectID)
            let assets = store.assetProvider(for: projectID)
            let r = try await Task.detached(priority: .userInitiated) { try TendiesExporter.export(p, assets: assets) }.value
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(r.fileName)
            try r.data.write(to: url, options: .atomic)
            result = r; fileURL = url; Haptics.success()
        } catch { self.error = error.localizedDescription; Haptics.error() }
        working = false
    }
}
