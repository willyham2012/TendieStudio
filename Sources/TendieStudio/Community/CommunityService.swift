import Foundation
import UIKit
import ImageIO

/// Read-only client for CAPlayground's PUBLIC community collection.
///
/// What was verified (from CAPlayground's open-source site code):
///  - The gallery is one static JSON file in the public GitHub repo
///    CAPlayground/wallpapers (wallpapers.json) with `base_url` + items.
///  - Files/previews are plain static files under that base URL.
///  - There is NO public publishing API: the website opens a pull request
///    against that repo (branch `dev`) using the user's signed-in session,
///    and maintainers review it. TendieStudio therefore never publishes;
///    it hands the user a validated .tendies and links them to that flow.
struct CommunityWallpaper: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let creator: String
    let description: String
    let file: String
    let preview: String
    let date: Date?

    enum CodingKeys: String, CodingKey { case id, name, creator, description, file, preview, date }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) } else { id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString }
        name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled"
        creator = (try? c.decode(String.self, forKey: .creator)) ?? "Unknown"
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        file = try c.decode(String.self, forKey: .file)
        preview = (try? c.decode(String.self, forKey: .preview)) ?? ""
        date = (try? c.decode(Double.self, forKey: .date)).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    var categories: [CommunityCategory] { CommunityCategory.matching(name: name, description: description) }
}

/// The source data has no categories, so these are derived locally from keywords
/// in the name and description. They are a convenience, not authoritative.
enum CommunityCategory: String, CaseIterable, Identifiable {
    case anime = "Anime & Games", cars = "Cars", abstract = "Abstract", apple = "Apple", space = "Space", nature = "Nature", aod = "Always-On"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .anime: return "gamecontroller"; case .cars: return "car.side"; case .abstract: return "circle.hexagongrid"
        case .apple: return "apple.logo"; case .space: return "moon.stars"; case .nature: return "leaf"; case .aod: return "moon.zzz"
        }
    }
    private var keywords: [String] {
        switch self {
        case .anime: return ["anime", "danganronpa", "genshin", "game", "minecraft", "naruto", "jojo", "pokemon", "zelda", "persona", "manga", "waifu", "sonic", "mario", "undertale", "blasphemous", "fnaf"]
        case .cars: return ["car", "audi", "bmw", "porsche", "ferrari", "lambo", "mclaren", "tesla", "nissan", "toyota", "mustang", "f1", "drift"]
        case .abstract: return ["abstract", "shape", "gradient", "blob", "minimal", "pattern", "geometric", "liquid", "ball", "glass", "orb"]
        case .apple: return ["apple", "ios", "iphone", "wwdc", "maps", "macos", "liquid glass", "ipados"]
        case .space: return ["space", "star", "galaxy", "planet", "moon", "earth", "nebula", "cosmos", "saturn", "death star"]
        case .nature: return ["nature", "forest", "ocean", "sea", "mountain", "flower", "rain", "tree", "sunset", "sky", "cloud", "beach"]
        case .aod: return ["aod", "always on", "always-on"]
        }
    }
    static func matching(name: String, description: String) -> [CommunityCategory] {
        let hay = (name + " " + description).lowercased()
        return allCases.filter { c in c.keywords.contains { hay.contains($0) } }
    }
}

@MainActor
final class CommunityService: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var items: [CommunityWallpaper] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var isOffline = false

    static let indexURL = URL(string: "https://raw.githubusercontent.com/CAPlayground/wallpapers/refs/heads/main/wallpapers.json")!
    private var baseURL = "https://raw.githubusercontent.com/CAPlayground/wallpapers/refs/heads/main/"
    private let cacheFile: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return d.appendingPathComponent("community-wallpapers.json")
    }()

    /// One malformed entry must not take down the whole collection.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from d: Decoder) throws { value = try? T(from: d) }
    }
    private struct Index: Decodable { let base_url: String; let wallpapers: [Lossy<CommunityWallpaper>] }

    func refresh() async {
        if state == .loading { return }
        state = .loading
        do {
            var req = URLRequest(url: Self.indexURL); req.timeoutInterval = 20
            req.cachePolicy = .reloadRevalidatingCacheData
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try apply(data)
            try? data.write(to: cacheFile, options: .atomic)
            isOffline = false; state = .loaded
        } catch {
            if let cached = try? Data(contentsOf: cacheFile), (try? apply(cached)) != nil {
                isOffline = true; state = .loaded
            } else { state = .failed("Couldn’t reach the community collection. Everything else still works offline.") }
        }
    }

    private func apply(_ data: Data) throws {
        let idx = try JSONDecoder().decode(Index.self, from: data)
        baseURL = idx.base_url
        items = idx.wallpapers.compactMap(\.value).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func fileURL(_ w: CommunityWallpaper) -> URL? { url(for: w.file) }
    func previewURL(_ w: CommunityWallpaper) -> URL? { w.preview.isEmpty ? nil : url(for: w.preview) }
    private func url(for path: String) -> URL? {
        URL(string: baseURL + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path))
    }

    enum DownloadError: LocalizedError {
        case badURL, tooLarge, invalid([String])
        var errorDescription: String? {
            switch self { case .badURL: return "Bad download address."; case .tooLarge: return "File is larger than the 120 MB limit."
            case .invalid(let e): return "Downloaded file doesn’t match the .tendies layout: " + e.joined(separator: "; ") }
        }
    }

    func download(_ w: CommunityWallpaper) async throws -> Data {
        guard let u = fileURL(w) else { throw DownloadError.badURL }
        let (data, resp) = try await URLSession.shared.data(from: u)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard data.count < 120 * 1024 * 1024 else { throw DownloadError.tooLarge }
        let r = TendiesValidator.validate(data)
        guard r.isValid else { throw DownloadError.invalid(r.errors) }
        return data
    }
}

/// Downsampled first-frame thumbnails for the grid. Decoding only the first frame
/// at thumbnail size keeps memory and battery low while scrolling.
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSURL, UIImage>()
    func thumbnail(for url: URL, maxPixel: Int = 420) async -> UIImage? {
        if let c = cache.object(forKey: url as NSURL) { return c }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = UIImage(cgImage: cg)
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
    func data(for url: URL) async -> Data? { try? await URLSession.shared.data(from: url).0 }
}
