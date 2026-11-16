import Foundation
import UIKit

/// Local-first storage. Layout under Application Support/TendieStudio:
///   Projects/<uuid>.tsproj/{project.json, assets/*, thumbnail.jpg}
///   Imports/<uuid>/{wallpaper.tendies, meta.json, preview.png}
/// Writes are atomic (temp file + replace) so a crash can never leave a
/// half-written project.json.
struct ImportedWallpaper: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var creator: String?
    var source: String          // "community" or "file"
    var addedAt: Date
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ProjectSummary] = []
    @Published private(set) var imports: [ImportedWallpaper] = []

    let root: URL
    private var projectsDir: URL { root.appendingPathComponent("Projects", isDirectory: true) }
    private var importsDir: URL { root.appendingPathComponent("Imports", isDirectory: true) }
    private let fm = FileManager.default

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TendieStudio", isDirectory: true)
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: importsDir, withIntermediateDirectories: true)
        reload()
    }

    // MARK: Paths
    func projectDir(_ id: UUID) -> URL { projectsDir.appendingPathComponent("\(id.uuidString).tsproj", isDirectory: true) }
    func assetsDir(_ id: UUID) -> URL { projectDir(id).appendingPathComponent("assets", isDirectory: true) }
    func importDir(_ id: UUID) -> URL { importsDir.appendingPathComponent(id.uuidString, isDirectory: true) }
    func importFile(_ id: UUID) -> URL { importDir(id).appendingPathComponent("wallpaper.tendies") }
    func importPreview(_ id: UUID) -> URL { importDir(id).appendingPathComponent("preview.png") }

    // MARK: Listing
    func reload() {
        let dirs = (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        var list: [ProjectSummary] = []
        for d in dirs where d.pathExtension == "tsproj" {
            guard let p = try? loadProject(at: d) else { continue }
            let thumb = d.appendingPathComponent("thumbnail.jpg")
            list.append(ProjectSummary(id: p.id, name: p.name, modifiedAt: p.modifiedAt, layerCount: p.layers.count,
                                       thumbnailURL: fm.fileExists(atPath: thumb.path) ? thumb : nil))
        }
        projects = list.sorted { $0.modifiedAt > $1.modifiedAt }
        let idirs = (try? fm.contentsOfDirectory(at: importsDir, includingPropertiesForKeys: nil)) ?? []
        imports = idirs.compactMap { d in
            (try? Data(contentsOf: d.appendingPathComponent("meta.json"))).flatMap { try? JSONDecoder.store.decode(ImportedWallpaper.self, from: $0) }
        }.sorted { $0.addedAt > $1.addedAt }
    }

    // MARK: Projects
    private func loadProject(at dir: URL) throws -> WallpaperProject {
        try JSONDecoder.store.decode(WallpaperProject.self, from: Data(contentsOf: dir.appendingPathComponent("project.json")))
    }
    func load(_ id: UUID) throws -> WallpaperProject { try loadProject(at: projectDir(id)) }

    func save(_ project: WallpaperProject, thumbnail: UIImage? = nil) throws {
        var p = project; p.modifiedAt = Date()
        try fm.createDirectory(at: assetsDir(p.id), withIntermediateDirectories: true)
        let data = try JSONEncoder.store.encode(p)
        try data.write(to: projectDir(p.id).appendingPathComponent("project.json"), options: .atomic)
        if let t = thumbnail?.jpegData(compressionQuality: 0.8) {
            try? t.write(to: projectDir(p.id).appendingPathComponent("thumbnail.jpg"), options: .atomic)
        }
        if let i = projects.firstIndex(where: { $0.id == p.id }) {
            projects[i].name = p.name; projects[i].modifiedAt = p.modifiedAt; projects[i].layerCount = p.layers.count
            if thumbnail != nil { projects[i].thumbnailURL = projectDir(p.id).appendingPathComponent("thumbnail.jpg") }
        } else { reload() }
        projects.sort { $0.modifiedAt > $1.modifiedAt }
    }

    @discardableResult
    func create(named name: String, device: DevicePreset = .iPhone14ProMax) throws -> WallpaperProject {
        var p = WallpaperProject.blank(name: name)
        p.canvasWidth = device.width; p.canvasHeight = device.height
        try save(p); return p
    }

    func duplicate(_ id: UUID) throws {
        var p = try load(id)
        let newID = UUID()
        try fm.copyItem(at: projectDir(id), to: projectDir(newID))
        p.id = newID; p.name += " copy"; p.createdAt = Date()
        try save(p); reload()
    }

    func delete(_ id: UUID) { try? fm.removeItem(at: projectDir(id)); projects.removeAll { $0.id == id } }

    func rename(_ id: UUID, to name: String) throws { var p = try load(id); p.name = name; try save(p) }

    /// Adds image data to a project's assets, normalised to PNG and capped in size
    /// so memory and export size stay small. Returns the asset file name.
    func addImage(_ image: UIImage, to projectID: UUID, maxDimension: CGFloat = 2048) throws -> (name: String, size: CGSize) {
        let scaled = image.normalized(maxDimension: maxDimension)
        guard let png = scaled.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let name = "img_\(UUID().uuidString.prefix(8).lowercased()).png"
        try fm.createDirectory(at: assetsDir(projectID), withIntermediateDirectories: true)
        try png.write(to: assetsDir(projectID).appendingPathComponent(name), options: .atomic)
        return (name, CGSize(width: scaled.size.width, height: scaled.size.height))
    }

    func assetProvider(for id: UUID) -> AssetProvider { DirectoryAssets(dir: assetsDir(id)) }

    // MARK: Imports
    @discardableResult
    func addImport(data: Data, name: String, creator: String?, source: String) throws -> ImportedWallpaper {
        let item = ImportedWallpaper(id: UUID(), name: name, creator: creator, source: source, addedAt: Date())
        try fm.createDirectory(at: importDir(item.id), withIntermediateDirectories: true)
        try data.write(to: importFile(item.id), options: .atomic)
        try JSONEncoder.store.encode(item).write(to: importDir(item.id).appendingPathComponent("meta.json"), options: .atomic)
        if let info = TendiesImporter.inspect(data), let p = info.previewImageData { try? p.write(to: importPreview(item.id)) }
        reload(); return item
    }
    func deleteImport(_ id: UUID) { try? fm.removeItem(at: importDir(id)); imports.removeAll { $0.id == id } }

    /// Turns an imported wallpaper into an editable project (static layers only).
    func makeEditable(_ item: ImportedWallpaper) throws -> (WallpaperProject, [String]) {
        let data = try Data(contentsOf: importFile(item.id))
        let r = try TendiesImporter.makeProject(from: data, name: item.name)
        try save(r.project)
        try fm.createDirectory(at: assetsDir(r.project.id), withIntermediateDirectories: true)
        for (n, d) in r.assets { try d.write(to: assetsDir(r.project.id).appendingPathComponent(n), options: .atomic) }
        return (r.project, r.notes)
    }
}

struct DirectoryAssets: AssetProvider {
    let dir: URL
    func assetData(named: String) -> Data? { try? Data(contentsOf: dir.appendingPathComponent(named)) }
}

extension JSONEncoder {
    static var store: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }
}
extension JSONDecoder {
    static var store: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

extension UIImage {
    /// Redraws to sRGB at scale 1, honouring EXIF orientation, capped to maxDimension.
    func normalized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        let k = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false
        return UIGraphicsImageRenderer(size: target, format: f).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
