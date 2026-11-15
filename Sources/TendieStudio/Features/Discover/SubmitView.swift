import SwiftUI

/// Guided submission to the CAPlayground community.
/// There is no public publishing API (CAPlayground's site opens a GitHub pull
/// request against CAPlayground/wallpapers on the user's behalf and maintainers
/// review it). We do not automate or bypass that: this screen prepares a
/// validated file and links to the official flow.
struct SubmitView: View {
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var exported: URL?
    @State private var report: ValidationReport?
    @State private var warnings: [String] = []
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Share with the community").font(.title2.weight(.bold))
                        Text("Community wallpapers are reviewed by CAPlayground’s maintainers. TendieStudio can’t publish for you — it prepares a validated file and takes you to the official submission flow.")
                            .font(.callout).foregroundStyle(.secondary)
                        step(1, "Pick a project") {
                            if store.projects.isEmpty { Text("Create a wallpaper in Studio first.").foregroundStyle(.secondary) }
                            else {
                                Picker("Project", selection: $selection) {
                                    Text("Choose…").tag(UUID?.none)
                                    ForEach(store.projects) { Text($0.name).tag(UUID?.some($0.id)) }
                                }.pickerStyle(.menu)
                            }
                        }
                        step(2, "Export & validate") {
                            Button { Task { await export() } } label: {
                                HStack { if busy { ProgressView() }; Text("Export .tendies") }
                            }.buttonStyle(PrimaryButtonStyle()).disabled(selection == nil || busy)
                            if let r = report { ReportView(report: r, warnings: warnings) }
                            if let error { Text(error).foregroundStyle(.red).font(.caption) }
                            if let exported { ShareLink(item: exported) { Label("Save / share file", systemImage: "square.and.arrow.up") } }
                        }
                        step(3, "Record a short preview") {
                            Text("The submission form asks for a preview video (.mp4 or .mov). Screen-record your wallpaper on the lock screen or in Studio’s preview.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        step(4, "Submit on CAPlayground") {
                            Link(destination: URL(string: "https://caplayground.vercel.app/wallpapers")!) {
                                Label("Open the CAPlayground wallpapers page", systemImage: "safari")
                            }
                            Text("You’ll need a CAPlayground account there. Submissions wait for maintainer review.").font(.caption).foregroundStyle(.secondary)
                            Link("Browse the repository", destination: URL(string: "https://github.com/CAPlayground/wallpapers")!).font(.caption)
                        }
                    }.padding(20)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func step<C: View>(_ n: Int, _ title: String, @ViewBuilder _ body: () -> C) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").font(.headline).frame(width: 30, height: 30).background(Theme.accentGradient, in: Circle()).foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); body() }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard()
    }

    private func export() async {
        guard let id = selection else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let p = try store.load(id)
            let assets = store.assetProvider(for: id)
            let r = try await Task.detached { try TendiesExporter.export(p, assets: assets) }.value
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(r.fileName)
            try r.data.write(to: url, options: .atomic)
            exported = url; report = r.report; warnings = r.warnings; Haptics.success()
        } catch { exported = nil; self.error = error.localizedDescription; Haptics.error() }
    }
}

struct ReportView: View {
    let report: ValidationReport
    let warnings: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(report.isValid ? "Matches the real .tendies layout" : "Validation failed", systemImage: report.isValid ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .foregroundStyle(report.isValid ? .green : .red).font(.subheadline.weight(.semibold))
            Text("\(report.layerCount) layers • \(report.animationCount) animations").font(.caption).foregroundStyle(.secondary)
            ForEach(report.errors, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.red) }
            ForEach(warnings, id: \.self) { Text("⚠︎ \($0)").font(.caption).foregroundStyle(.orange) }
            Text("Structure is validated offline against real files. Whether your iOS version renders it still needs a device test.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
