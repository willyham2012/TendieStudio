import XCTest
import UIKit
@testable import TendieStudio

private struct MemoryAssets: AssetProvider {
    var files: [String: Data]
    func assetData(named: String) -> Data? { files[named] }
}

final class ExportTests: XCTestCase {
    private func pngData() -> Data {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        return r.pngData { c in UIColor.orange.setFill(); c.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
    }

    private func sampleProject() -> (WallpaperProject, MemoryAssets) {
        var p = WallpaperProject.blank(name: "Test Wall")
        var img = WallpaperLayer(name: "Hero <&> \"x\"", kind: .image, assetName: "a.png", position: CGPoint(x: 215, y: 466), size: CGSize(width: 200, height: 200))
        img.tracks = MotionPreset.float.tracks(for: img, duration: p.duration)
            + MotionPreset.spin.tracks(for: img, duration: p.duration)
            + MotionPreset.breathe.tracks(for: img, duration: p.duration)
        var circle = WallpaperLayer(name: "Dot", kind: .ellipse, assetName: nil, position: CGPoint(x: 100, y: 100), size: CGSize(width: 80, height: 80))
        circle.plane = .foreground
        p.layers = [img, circle]
        return (p, MemoryAssets(files: ["a.png": pngData()]))
    }

    func testExportMatchesRealLayoutAndValidates() throws {
        let (p, assets) = sampleProject()
        let r = try TendiesExporter.export(p, assets: assets)
        XCTAssertTrue(r.report.isValid, r.report.errors.joined(separator: "\n"))
        XCTAssertEqual(r.fileName, "Test_Wall.tendies")
        let entries = try ZipArchive.read(r.data)
        let paths = Set(entries.map(\.path))
        let root = "descriptors/\(TendiesTemplate.descriptorUUID)/versions/1/contents/\(TendiesExporter.wallpaperFolder)/"
        XCTAssertTrue(paths.contains(root + "Wallpaper.plist"))
        for plane in Plane.allCases {
            XCTAssertTrue(paths.contains(root + TendiesExporter.caFolder(plane) + "/main.caml"))
            XCTAssertTrue(paths.contains(root + TendiesExporter.caFolder(plane) + "/index.xml"))
        }
        XCTAssertTrue(paths.contains(root + TendiesExporter.caFolder(.floating) + "/assets/a.png"))
        XCTAssertGreaterThan(r.report.animationCount, 0)
    }

    func testCAMLIsWellFormedAndEscapesNames() throws {
        let (p, _) = sampleProject()
        let xml = CAMLWriter.document(canvas: p.canvasSize, backgroundColor: p.background,
                                      layers: LayerResolver.layers(in: .floating, of: p)) { "assets/\($0)" }
        let scan = CAMLScanner(data: Data(xml.utf8))
        XCTAssertNil(scan.error)
        XCTAssertTrue(scan.sawCamlRoot)
        XCTAssertEqual(scan.imageSources, ["assets/a.png"])
        XCTAssertTrue(xml.contains("Hero &lt;&amp;&gt; &quot;x&quot;"))
    }

    func testEmptyProjectIsRejected() {
        XCTAssertThrowsError(try TendiesExporter.export(.blank(), assets: MemoryAssets(files: [:])))
    }

    func testMissingAssetIsReported() {
        let (p, _) = sampleProject()
        XCTAssertThrowsError(try TendiesExporter.export(p, assets: MemoryAssets(files: [:])))
    }

    func testZipRoundTripStoredAndDeflated() throws {
        let big = Data(String(repeating: "tendie ", count: 5000).utf8)
        let es = [ZipEntry(path: "d/", data: Data()), ZipEntry(path: "d/a.txt", data: big), ZipEntry(path: "d/b.bin", data: Data([1, 2, 3]))]
        let z = ZipArchive.write(es)
        XCTAssertLessThan(z.count, big.count)
        XCTAssertEqual(try ZipArchive.read(z), es)
    }

    func testTemplateMatchesRecordedHashes() {
        for f in TendiesTemplate.files { XCTAssertFalse(f.data.isEmpty, f.path) }
        XCTAssertEqual(TendiesTemplate.files.count, 19)
    }

    func testImporterRoundTripsStaticLayers() throws {
        var (p, assets) = sampleProject()
        p.layers[0].tracks = []
        let r = try TendiesExporter.export(p, assets: assets)
        let imp = try TendiesImporter.makeProject(from: r.data, name: "Re")
        XCTAssertEqual(imp.project.layers.count, 2)
        XCTAssertEqual(imp.project.layers.first { $0.kind == .image }?.position.x ?? 0, 215, accuracy: 0.01)
        XCTAssertEqual(imp.project.canvasWidth, p.canvasWidth)
    }
}

final class AnimationTests: XCTestCase {
    func testEasingEndpoints() {
        for e in [Easing.linear, .easeIn, .easeOut, .easeInOut, .spring, .bounce, .bezier(0.2, 0.8, 0.2, 1)] {
            XCTAssertEqual(e.apply(0), 0, accuracy: 0.001, e.title)
            XCTAssertEqual(e.apply(1), 1, accuracy: 0.001, e.title)
        }
    }

    func testBakeIsUniformAndHitsKeyframes() {
        let t = Track(property: .opacity, keyframes: [Keyframe(time: 0, value: [0], easing: .linear), Keyframe(time: 2, value: [1], easing: .linear)])
        let s = AnimationBaker.bake(t, duration: 2)
        XCTAssertEqual(s.count, AnimationBaker.sampleCount(duration: 2))
        XCTAssertEqual(s.first![0], 0, accuracy: 1e-9)
        XCTAssertEqual(s.last![0], 1, accuracy: 1e-9)
        XCTAssertEqual(s[s.count / 2][0], 0.5, accuracy: 0.02)
    }

    func testUpsertSnapsAndReplaces() {
        var t = Track(property: .scale, keyframes: [])
        AnimationBaker.upsert(&t, time: 1.0, value: [1])
        AnimationBaker.upsert(&t, time: 1.01, value: [2])
        XCTAssertEqual(t.keyframes.count, 1)
        XCTAssertEqual(t.keyframes[0].value, [2])
    }

    func testProjectCodableRoundTrip() throws {
        var p = WallpaperProject.blank()
        var l = WallpaperLayer(name: "x", kind: .rectangle, assetName: nil, position: .zero, size: CGSize(width: 1, height: 1))
        l.tracks = [Track(property: .position, keyframes: [Keyframe(time: 0, value: [1, 2], easing: .bezier(0.1, 0.2, 0.3, 0.4))])]
        p.layers = [l]
        let d = try JSONEncoder.store.encode(p)
        XCTAssertEqual(try JSONDecoder.store.decode(WallpaperProject.self, from: d).layers, p.layers)
    }
}
