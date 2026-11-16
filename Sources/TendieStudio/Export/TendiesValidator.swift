import Foundation

/// Structural validation of a .tendies, mirroring Tools/validate_tendies.py
/// (which was run against 15 real community wallpapers). This proves the file
/// matches the real layout; only a device can prove PosterBoard accepts it.
struct ValidationReport {
    var errors: [String] = []
    var warnings: [String] = []
    var layerCount = 0
    var animationCount = 0
    var isValid: Bool { errors.isEmpty }
}

enum TendiesValidator {
    static func validate(_ data: Data) -> ValidationReport {
        var r = ValidationReport()
        let entries: [ZipEntry]
        do { entries = try ZipArchive.read(data) } catch { r.errors.append("\(error.localizedDescription)"); return r }
        return validate(entries)
    }

    static func validate(_ all: [ZipEntry]) -> ValidationReport {
        var r = ValidationReport()
        let entries = all.filter { !$0.path.contains("DS_Store") && !$0.path.contains("__MACOSX") }
        let map = Dictionary(entries.map { ($0.path, $0.data) }, uniquingKeysWith: { a, _ in a })
        if entries.contains(where: { $0.path.lowercased().contains("com.apple.mercuryposter") }) {
            r.errors.append("Mercury poster container is not supported"); return r
        }
        let wps = entries.map(\.path).filter { $0.hasSuffix("/Wallpaper.plist") }
        guard wps.count == 1, let wp = wps.first else {
            r.errors.append("Expected exactly one Wallpaper.plist, found \(wps.count)"); return r
        }
        let comps = wp.split(separator: "/").map(String.init)
        guard comps.count == 7, comps[0] == "descriptors", comps[2] == "versions", comps[4] == "contents", comps[5].hasSuffix(".wallpaper") else {
            r.errors.append("Wallpaper.plist is at an unexpected path: \(wp)"); return r
        }
        let descriptorRoot = "descriptors/\(comps[1])"
        let contentsRoot = "\(descriptorRoot)/versions/\(comps[3])/contents"
        for f in ["com.apple.posterkit.provider.descriptor.identifier", "com.apple.posterkit.role.identifier", "providerInfo.plist"]
        where map["\(descriptorRoot)/\(f)"] == nil { r.errors.append("Missing descriptor file \(f)") }
        let ui = "\(contentsRoot)/com.apple.posterkit.provider.contents.userInfo"
        if let d = map[ui] {
            if let p = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any] {
                if p["wallpaperRepresentingFileName"] as? String != comps[5] {
                    r.errors.append("userInfo wallpaperRepresentingFileName does not match the .wallpaper folder")
                }
            } else { r.errors.append("userInfo is not a valid property list") }
        } else { r.errors.append("Missing contents userInfo") }

        guard let wpData = map[wp],
              let root = try? PropertyListSerialization.propertyList(from: wpData, options: [], format: nil) as? [String: Any],
              let assets = root["assets"] as? [String: Any],
              let lock = assets["lockAndHome"] as? [String: Any],
              let def = lock["default"] as? [String: Any] else {
            r.errors.append("Wallpaper.plist has an unexpected shape"); return r
        }
        if def["type"] as? String != "LayeredAnimation" { r.errors.append("Wallpaper.plist type must be LayeredAnimation") }
        let refs = ["foregroundAnimationFileName", "backgroundAnimationFileName", "floatingAnimationFileNameKey"]
            .compactMap { def[$0] as? String }
        if refs.count != 3 { r.warnings.append("Not all three planes are referenced") }
        let base = wp.replacingOccurrences(of: "/Wallpaper.plist", with: "") + "/"
        for ref in refs {
            let ca = base + ref + "/"
            guard entries.contains(where: { $0.path.hasPrefix(ca) }) else { r.errors.append("Missing package \(ref)"); continue }
            guard let idx = map[ca + "index.xml"],
                  let ip = try? PropertyListSerialization.propertyList(from: idx, options: [], format: nil) as? [String: Any],
                  let rootDoc = ip["rootDocument"] as? String else { r.errors.append("\(ref): index.xml missing or invalid"); continue }
            guard let caml = map[ca + rootDoc] else { r.errors.append("\(ref): \(rootDoc) missing"); continue }
            if map[ca + "assetManifest.caml"] == nil { r.warnings.append("\(ref): no assetManifest.caml") }
            let scan = CAMLScanner(data: caml)
            if let e = scan.error { r.errors.append("\(ref): \(rootDoc) is not well-formed XML (\(e))"); continue }
            if !scan.sawCamlRoot { r.errors.append("\(ref): root element must be <caml>") }
            for src in scan.imageSources where !src.hasPrefix("data:") && map[ca + src] == nil {
                r.errors.append("\(ref): image \(src) missing from package")
            }
            r.layerCount += scan.layerCount; r.animationCount += scan.animationCount
        }
        return r
    }
}

/// Counts layers/animations/images in a CAML document and checks well-formedness.
final class CAMLScanner: NSObject, XMLParserDelegate {
    var layerCount = 0, animationCount = 0
    var imageSources: [String] = []
    var sawCamlRoot = false
    var error: String?
    private var depth = 0
    init(data: Data) {
        super.init()
        let p = XMLParser(data: data)
        p.delegate = self
        if !p.parse() { error = p.parserError?.localizedDescription ?? "parse failed" }
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        if depth == 0 { sawCamlRoot = (name == "caml") }
        depth += 1
        switch name {
        case "CALayer", "CATextLayer", "CAGradientLayer", "CAShapeLayer": layerCount += 1
        case "animation": animationCount += 1
        case "CGImage": if let s = a["src"] { imageSources.append(s) }
        default: break
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { depth -= 1 }
}
