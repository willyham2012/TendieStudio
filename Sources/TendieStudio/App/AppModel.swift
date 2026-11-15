import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
final class AppModel: ObservableObject {
    let store = ProjectStore()
    let community = CommunityService()
    @Published var editingProjectID: UUID?
    @Published var tab: AppTab = .studio
    @Published var toast: String?

    static let tendiesType = UTType(filenameExtension: "tendies") ?? .zip

    func newProject(named name: String = "Untitled", device: DevicePreset = .iPhone14ProMax) {
        do {
            let p = try store.create(named: name, device: device)
            Haptics.medium(); editingProjectID = p.id
        } catch { show("Couldn’t create project: \(error.localizedDescription)") }
    }

    func newProject(from image: UIImage, device: DevicePreset = .iPhone14ProMax) {
        do {
            var p = try store.create(named: "Photo wallpaper", device: device)
            let a = try store.addImage(image, to: p.id)
            p.layers.append(.image(name: "Photo", assetName: a.name, pixelSize: a.size, canvas: p.canvasSize, cover: true))
            try store.save(p)
            Haptics.medium(); editingProjectID = p.id
        } catch { show("Couldn’t create project: \(error.localizedDescription)") }
    }

    func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let report = TendiesValidator.validate(data)
            let name = url.deletingPathExtension().lastPathComponent
            try store.addImport(data: data, name: name, creator: nil, source: "file")
            if report.isValid { Haptics.success(); show("Imported “\(name)”") }
            else { Haptics.warning(); show("Imported, but it doesn’t match the known .tendies layout") }
            tab = .library
        } catch { Haptics.error(); show("Import failed: \(error.localizedDescription)") }
    }

    func show(_ message: String) {
        toast = message
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if toast == message { toast = nil } }
    }
}

enum AppTab: Hashable { case discover, studio, library }
