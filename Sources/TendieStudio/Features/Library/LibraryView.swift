import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProjectStore
    @State private var section = 0
    @State private var importing = false
    @State private var renaming: ProjectSummary?
    @State private var newName = ""
    @State private var exportTarget: ProjectSummary?
    @State private var showGuide = false
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        Picker("", selection: $section) { Text("Projects").tag(0); Text("Downloads & imports").tag(1) }
                            .pickerStyle(.segmented)
                        if section == 0 { projects } else { imports }
                    }.padding(.horizontal, 16).padding(.bottom, 40)
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showGuide = true } label: { Image(systemName: "questionmark.circle") }
                    Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [AppModel.tendiesType, .zip, .data]) { r in
                if case .success(let u) = r { app.importFile(u) }
            }
            .sheet(isPresented: $showGuide) { InstallGuideView() }
            .sheet(item: $exportTarget) { ExportSheet(projectID: $0.id) }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") { if let r = renaming, !newName.isEmpty { try? store.rename(r.id, to: newName) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }

    @ViewBuilder private var projects: some View {
        if store.projects.isEmpty {
            ContentUnavailableView("No projects yet", systemImage: "wand.and.stars", description: Text("Create your first wallpaper in the Studio tab. Everything is saved automatically."))
                .padding(.top, 40)
        } else {
            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(store.projects) { p in
                    Button { app.editingProjectID = p.id } label: { ProjectCard(summary: p) }.buttonStyle(PressScale())
                        .contextMenu {
                            Button { app.editingProjectID = p.id } label: { Label("Open", systemImage: "pencil") }
                            Button { newName = p.name; renaming = p } label: { Label("Rename", systemImage: "textformat") }
                            Button { try? store.duplicate(p.id); Haptics.success() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            Button { exportTarget = p } label: { Label("Export .tendies", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) { store.delete(p.id); Haptics.warning() } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
        }
    }

    @ViewBuilder private var imports: some View {
        if store.imports.isEmpty {
            ContentUnavailableView("Nothing here yet", systemImage: "arrow.down.circle", description: Text("Download wallpapers from Discover, or import a .tendies file with the button above."))
                .padding(.top, 40)
        } else {
            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(store.imports) { i in
                    ImportCard(item: i).contextMenu {
                        Button { do { let (p, n) = try store.makeEditable(i); app.show(n.first ?? "Opened in Studio"); app.editingProjectID = p.id } catch { app.show(error.localizedDescription) } } label: { Label("Make editable copy", systemImage: "pencil") }
                        ShareLink(item: store.importFile(i.id)) { Label("Share / Open in…", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) { store.deleteImport(i.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
    }
}

extension ProjectSummary: Hashable { func hash(into h: inout Hasher) { h.combine(id) } }

struct ProjectCard: View {
    let summary: ProjectSummary
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.inkRaised)
                if let u = summary.thumbnailURL, let img = UIImage(contentsOfFile: u.path) { Image(uiImage: img).resizable().scaledToFill() }
                else { Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.white.opacity(0.25)) }
            }
            .aspectRatio(0.5, contentMode: .fit).frame(width: compact ? 120 : nil)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(summary.layerCount) layers • \(summary.modifiedAt.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }.padding(.horizontal, 4)
        }
    }
}

struct ImportCard: View {
    @EnvironmentObject var store: ProjectStore
    let item: ImportedWallpaper
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.inkRaised)
                if let img = UIImage(contentsOfFile: store.importPreview(item.id).path) { Image(uiImage: img).resizable().scaledToFill() }
                else { Image(systemName: "tray.and.arrow.down").font(.largeTitle).foregroundStyle(.white.opacity(0.25)) }
            }.aspectRatio(0.5, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(item.creator.map { "by \($0)" } ?? (item.source == "file" ? "Imported file" : "Community")).font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 4)
        }
    }
}

struct InstallGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        block("What TendieStudio does", "Creates, edits, previews and exports .tendies files entirely on-device. Exported files are checked against the real file layout used by community wallpapers.", "checkmark.seal")
                        block("What it can’t do", "Setting a .tendies as your Lock Screen means writing into PosterBoard’s private container. A sandboxed app can’t do that — sideloading doesn’t change it. TendieStudio contains no exploit and doesn’t claim to install wallpapers.", "lock.shield")
                        block("How people install them", "Community tools such as Nugget (computer-based) and Pocket Poster (on-device) apply .tendies files. Use the Share button to send an exported file to them. Their support for your iOS version changes quickly — check their release notes; compatibility with iOS 27 has not been verified here.", "arrow.triangle.branch")
                        block("Please test", "Layouts are validated against real files offline, but only a device test proves a given iOS version renders your wallpaper. Report results so the app can note what works.", "iphone")
                        Link("Nugget on GitHub", destination: URL(string: "https://github.com/leminlimez/Nugget")!)
                        Link("Pocket Poster on GitHub", destination: URL(string: "https://github.com/leminlimez/Pocket-Poster")!)
                    }.padding(20)
                }
            }.navigationTitle("How to install").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
    private func block(_ t: String, _ b: String, _ i: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: i).font(.title3).foregroundStyle(Theme.amber).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) { Text(t).font(.headline); Text(b).font(.callout).foregroundStyle(.secondary) }
        }.padding(16).glassCard()
    }
}
