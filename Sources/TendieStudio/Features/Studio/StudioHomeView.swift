import SwiftUI
import PhotosUI

/// Studio tab landing: start something new or jump back into a draft.
struct StudioHomeView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProjectStore
    @State private var photoItem: PhotosPickerItem?
    @State private var device = DevicePreset.iPhone14ProMax

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Make it.").font(.system(size: 44, weight: .heavy, design: .rounded))
                            Text("Animate it. Keep it.").font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.accentGradient)
                            Text("Everything happens on your iPhone — no account, no cloud.")
                                .font(.callout).foregroundStyle(.secondary).padding(.top, 4)
                        }
                        VStack(spacing: 12) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                actionRow("photo.on.rectangle.angled", "Start from a photo", "Import an image and make it move")
                            }.buttonStyle(PressScale())
                            Button { app.newProject(device: device) } label: {
                                actionRow("plus.square.dashed", "Blank canvas", "Build from shapes and layers")
                            }.buttonStyle(PressScale())
                            Menu {
                                Picker("Canvas size", selection: $device) { ForEach(DevicePreset.all) { Text("\($0.name)  \(Int($0.width))×\(Int($0.height))").tag($0) } }
                            } label: {
                                Label("Canvas: \(device.name) • \(Int(device.width))×\(Int(device.height))", systemImage: "iphone.gen3")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if !store.projects.isEmpty {
                            SectionTitle("Continue editing")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(store.projects.prefix(8)) { p in
                                        Button { app.editingProjectID = p.id } label: { ProjectCard(summary: p, compact: true) }.buttonStyle(PressScale())
                                    }
                                }
                            }
                        }
                    }.padding(20).padding(.bottom, 40)
                }
            }
            .navigationTitle("Studio").navigationBarTitleDisplayMode(.inline)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { app.newProject(from: img, device: device) }
                    photoItem = nil
                }
            }
        }
    }

    private func actionRow(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).frame(width: 48, height: 48).background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(sub).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.padding(14).frame(maxWidth: .infinity).glassCard()
    }
}
