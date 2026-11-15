import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var community: CommunityService
    @EnvironmentObject var store: ProjectStore
    @State private var query = ""
    @State private var category: CommunityCategory?
    @State private var creatorFilter: String?
    @State private var selected: CommunityWallpaper?
    @State private var showSubmit = false

    private var filtered: [CommunityWallpaper] {
        community.items.filter { w in
            (category == nil || w.categories.contains(category!)) &&
            (creatorFilter == nil || w.creator == creatorFilter) &&
            (query.isEmpty || [w.name, w.creator, w.description].contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    private let cols = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        chips
                        content
                    }.padding(.horizontal, 16).padding(.bottom, 40)
                }
                .refreshable { await community.refresh() }
            }
            .navigationTitle("Discover")
            .searchable(text: $query, prompt: "Search wallpapers, creators")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSubmit = true } label: { Label("Share yours", systemImage: "square.and.arrow.up") }
                }
            }
            .task { if community.state == .idle { await community.refresh() } }
            .sheet(item: $selected) { w in WallpaperDetailView(wallpaper: w, filterCreator: { c in creatorFilter = c; selected = nil }) }
            .sheet(isPresented: $showSubmit) { SubmitView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Community collection").font(.title3.weight(.semibold))
            HStack(spacing: 6) {
                Image(systemName: community.isOffline ? "wifi.slash" : "link")
                Text(community.isOffline ? "Offline — showing the last saved list" : "From CAPlayground’s public collection • not affiliated")
            }.font(.caption).foregroundStyle(.secondary)
            if let c = creatorFilter {
                Button { creatorFilter = nil } label: { Label("By \(c)  ✕", systemImage: "person.crop.circle") }
                    .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6).glassCapsule(tint: Theme.amber)
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", "square.grid.2x2", category == nil) { category = nil }
                ForEach(CommunityCategory.allCases) { c in chip(c.rawValue, c.symbol, category == c) { category = (category == c ? nil : c) } }
            }
        }
    }
    private func chip(_ t: String, _ s: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button { Haptics.select(); withAnimation(.snappy) { a() } } label: {
            Label(t, systemImage: s).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(on ? .black : .white)
                .background { if on { Capsule().fill(Theme.accentGradient) } }
                .glassCapsule(interactive: true)
        }.buttonStyle(PressScale())
    }

    @ViewBuilder private var content: some View {
        if community.items.isEmpty {
            if case .failed(let m) = community.state {
                ContentUnavailableView { Label("No connection", systemImage: "wifi.slash") } description: { Text(m) } actions: {
                    Button("Try again") { Task { await community.refresh() } }.buttonStyle(PrimaryButtonStyle())
                }.padding(.top, 40)
            } else {
                ProgressView("Loading community…").frame(maxWidth: .infinity).padding(.top, 60)
            }
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: query).padding(.top, 40)
        } else {
            Text("\(filtered.count) wallpapers • categories are auto-tagged from names").font(.caption2).foregroundStyle(.tertiary)
            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(filtered) { w in
                    Button { Haptics.tap(); selected = w } label: { WallpaperCard(wallpaper: w) }.buttonStyle(PressScale())
                }
            }
        }
    }
}

struct WallpaperCard: View {
    @EnvironmentObject var community: CommunityService
    let wallpaper: CommunityWallpaper
    @State private var image: UIImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.inkRaised)
                if let image { Image(uiImage: image).resizable().scaledToFill().transition(.opacity) }
                else { ProgressView().tint(.white.opacity(0.4)) }
            }
            .aspectRatio(0.5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("by \(wallpaper.creator)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.padding(.horizontal, 4)
        }
        .task(id: wallpaper.id) {
            guard let u = community.previewURL(wallpaper) else { return }
            let img = await ThumbnailLoader.shared.thumbnail(for: u)
            withAnimation(.easeOut(duration: 0.25)) { image = img }
        }
    }
}

struct WallpaperDetailView: View {
    @EnvironmentObject var community: CommunityService
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let wallpaper: CommunityWallpaper
    var filterCreator: (String) -> Void
    @State private var gif: Data?
    @State private var downloading = false
    @State private var error: String?
    @State private var saved: ImportedWallpaper?
    @State private var info: TendiesInfo?

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.inkRaised)
                            if let gif { AnimatedGIFView(data: gif) } else { ProgressView() }
                        }
                        .aspectRatio(0.46, contentMode: .fit).frame(maxHeight: 480)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.15)))
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

                        VStack(spacing: 6) {
                            Text(wallpaper.name).font(.title2.weight(.bold))
                            Button { filterCreator(wallpaper.creator) } label: {
                                Label(wallpaper.creator, systemImage: "person.crop.circle").font(.subheadline)
                            }
                            if !wallpaper.description.isEmpty { Text(wallpaper.description).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                            if let d = wallpaper.date { Text("Published \(d.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.tertiary) }
                        }
                        if let info {
                            Text("\(info.layerCount) layers • \(info.animationCount) animations • \(info.imageCount) images")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        actions
                        Text("Wallpapers belong to their creators. Installing one on your iPhone needs an external tool such as Nugget or Pocket Poster — see Library › How to install.")
                            .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }.padding(20)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task {
                if let u = community.previewURL(wallpaper) { gif = await ThumbnailLoader.shared.data(for: u) }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private var actions: some View {
        if let saved {
            VStack(spacing: 10) {
                Label("Saved to Library", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                ShareLink(item: store.importFile(saved.id), preview: SharePreview(wallpaper.name)) {
                    Label("Share / Open in…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }.buttonStyle(PrimaryButtonStyle())
                Button("Make editable copy (layers only)") {
                    do { let (p, notes) = try store.makeEditable(saved); dismiss(); app.show(notes.first ?? "Opened in Studio"); app.editingProjectID = p.id }
                    catch { self.error = error.localizedDescription }
                }.font(.subheadline)
            }
        } else {
            Button { Task { await download() } } label: {
                HStack { if downloading { ProgressView().tint(.black) }; Text(downloading ? "Downloading…" : "Download to Library") }.frame(maxWidth: .infinity)
            }.buttonStyle(PrimaryButtonStyle()).disabled(downloading)
        }
        if let error { Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center) }
    }

    private func download() async {
        downloading = true; error = nil
        defer { downloading = false }
        do {
            let data = try await community.download(wallpaper)
            let item = try store.addImport(data: data, name: wallpaper.name, creator: wallpaper.creator, source: "community")
            info = TendiesImporter.inspect(data); saved = item; Haptics.success()
        } catch { Haptics.error(); self.error = error.localizedDescription }
    }
}
