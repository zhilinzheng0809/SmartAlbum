import SwiftUI

/// 主标签页：相册 / 搜索 / 设置
struct MainTabView: View {
    @State private var selectedTab = 0

    let photoService: PhotoLibraryService
    let aiService: AIService
    let photoStore: PhotoStore

    var body: some View {
        TabView(selection: $selectedTab) {
            PhotoGridView(
                photoService: photoService,
                aiService: aiService,
                photoStore: photoStore
            )
            .tabItem {
                Label("相册", systemImage: "photo.on.rectangle")
            }
            .tag(0)

            SearchView(
                photoStore: photoStore,
                photoService: photoService
            )
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .tag(1)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(2)
        }
    }
}
