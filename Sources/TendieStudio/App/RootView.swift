import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $model.tab) {
                DiscoverView().tabItem { Label("Discover", systemImage: "sparkles.rectangle.stack") }.tag(AppTab.discover)
                StudioHomeView().tabItem { Label("Studio", systemImage: "wand.and.stars") }.tag(AppTab.studio)
                LibraryView().tabItem { Label("Library", systemImage: "square.stack.3d.down.right") }.tag(AppTab.library)
            }
            if let t = model.toast {
                Text(t).font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                    .glassCapsule().padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.toast)
        .fullScreenCover(item: Binding(get: { model.editingProjectID.map(IDBox.init) }, set: { model.editingProjectID = $0?.id })) { box in
            EditorView(projectID: box.id, store: model.store)
        }
    }
}

struct IDBox: Identifiable { let id: UUID }
