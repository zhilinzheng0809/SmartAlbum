import SwiftUI

@main
struct SmartAlbumApp: App {

    @StateObject private var photoService = PhotoLibraryService()
    @StateObject private var photoStore = PhotoStore()
    private let aiService = AIService()

    var body: some Scene {
        WindowGroup {
            MainTabView(
                photoService: photoService,
                aiService: aiService,
                photoStore: photoStore
            )
            .onAppear {
                Task {
                    _ = await photoService.requestAuthorization()
                }
            }
        }
    }
}
