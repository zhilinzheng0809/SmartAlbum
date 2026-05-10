import Foundation
import Combine

/// 搜索页 ViewModel
@MainActor
final class SearchViewModel: ObservableObject {

    @Published var searchText = ""
    @Published var searchResults: [PhotoRecord] = []
    @Published var isSearching = false

    private let photoStore: PhotoStore

    init(photoStore: PhotoStore) {
        self.photoStore = photoStore
    }

    func search() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        searchResults = photoStore.search(query: query)
    }
}
