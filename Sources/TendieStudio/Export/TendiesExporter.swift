import Foundation

protocol AssetProvider { func assetData(named: String) -> Data? }

struct ExportResult {
    var data: Data
    var report: ValidationReport
    var fileName: String
    var warnings: [String]
}

enum ExportError: LocalizedError {
    case missingAsset(String), emptyProject, invalidOutput([String])
    var errorDescription: String? {
        switch self {
        case .missingAsset(let n): return "Image “\(n)” is missing from the project."
        case .emptyProject: return "Add at least one layer before exporting."
        case .invalidOutput(let e): return "Export failed validation: " + e.joined(separator: "; ")
        }
    }
}

/// Builds a .tendies using the real descriptor/ContentsV1 layout that all
/// inspected community wallpapers share. Template plists are embedded verbatim
/// (TendiesTemplate); only the three .ca packages are generated.
enum TendiesExporter {
    // Names are identical across all 16 real samples we inspected, regardless of device.
    static let wallpaperFolder = "7400.WWDC_2022-390w-844h@3x~iphone.wallpaper"
    static func caFolder(_ p: Plane) -> String { "7400.WWDC_2022_\(p.caName)-390w-844h@3x~iphone.ca" }

    static func export(_ project: WallpaperProject, assets: AssetProvider) throws -> ExportResult {
        guard project.layers.contains(where: { !$0.isHidden }) else { throw ExportError.emptyProject }
        var warnings: [String] = []
        let root = "descriptors/\(TendiesTemplate.descriptorUUID)/"
        let wallpaperDir = root + "versions/1/contents/\(wallpaperFolder)/"
        var files: [String: Data] = [:]

        for f in TendiesTemplate.files {
            // Per-plane Foreground index carries document size in the real template.
            files[root + f.path] = f.data
        }

        // Update the Foreground index.xml document size (the real template hard-codes 390x844).
        let fgIndex = wallpaperDir + caFolder(.foreground) + "/index.xml"
        if let d = files[fgIndex], var s = String(data: d, encoding: .utf8) {
            s = s.replacingOccurrences(of: "<key>documentHeight</key>\n\t<real>844</real>",
                                       with: "<key>documentHeight</key>\n\t<real>\(CAMLWriter.num(project.canvasHeight))</real>")
            s = s.replacingOccurrences(of: "<key>documentWidth</key>\n\t<real>390</real>",
                                       with: "<key>documentWidth</key>\n\t<real>\(CAMLWriter.num(project.canvasWidth))</real>")
            files[fgIndex] = Data(s.utf8)
        }

        var usedAssets = Set<String>()
        for plane in Plane.allCases {
            let layers = LayerResolver.layers(in: plane, of: project)
            let dir = wallpaperDir + caFolder(plane) + "/"
            let bg: RGBA? = plane == .background ? project.background : nil
            let caml = CAMLWriter.document(canvas: project.canvasSize, backgroundColor: bg, layers: layers) { "assets/\($0)" }
            files[dir + "main.caml"] = Data(caml.utf8)
            for l in layers {
                guard l.kind == .image, let name = l.assetName else { continue }
                let key = dir + "assets/" + name
                if files[key] != nil { continue }
                guard let d = assets.assetData(named: name) else { throw ExportError.missingAsset(name) }
                files[key] = d; usedAssets.insert(name)
            }
        }
        if project.layers.contains(where: { l in l.track(.scale) != nil && l.track(.rotation) != nil }) {
            warnings.append("A layer animates both scale and rotation. Separate transform.scale and transform.rotation.z animations are standard Core Animation but were not present in the real wallpapers used for validation — test on device.")
        }
        if project.layers.contains(where: { $0.track(.scale) != nil }) {
            warnings.append("Scale animation uses keyPath transform.scale, which was not seen in the validated community samples (position, rotation.z and opacity were). Test on device.")
        }
        let w = project.canvasWidth, h = project.canvasHeight
        if (w, h) != (390, 844) {
            warnings.append("Canvas is \(Int(w))×\(Int(h)); real community wallpapers use varying document sizes inside the standard 390w-844h@3x folder name, but a 14 Pro Max (430×932) result must be confirmed on device.")
        }

        // Entry order: directories first (like the real files), then files sorted by path.
        var dirs = Set<String>()
        for path in files.keys {
            var parts = path.split(separator: "/").map(String.init)
            parts.removeLast()
            for i in 1...max(1, parts.count) where i <= parts.count { dirs.insert(parts[0..<i].joined(separator: "/") + "/") }
        }
        var entries = dirs.sorted().map { ZipEntry(path: $0, data: Data()) }
        entries += files.keys.sorted().map { ZipEntry(path: $0, data: files[$0]!) }

        let zip = ZipArchive.write(entries)
        let report = TendiesValidator.validate(zip)
        guard report.isValid else { throw ExportError.invalidOutput(report.errors) }
        let safe = project.name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        let base = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return ExportResult(data: zip, report: report, fileName: (base.isEmpty ? "Wallpaper" : base) + ".tendies", warnings: warnings)
    }
}
