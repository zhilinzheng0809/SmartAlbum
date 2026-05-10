import Foundation
import Combine
import SwiftUI
import Photos

/// 展示用的照片数据对象
struct PhotoAsset: Identifiable {
    let id: String
    let asset: PHAsset
    let thumbnail: UIImage?
    let record: PhotoRecord?

    init(asset: PHAsset, thumbnail: UIImage? = nil, record: PhotoRecord? = nil) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.thumbnail = thumbnail
        self.record = record
    }
}

/// 照片网格页 ViewModel
@MainActor
final class PhotoGridViewModel: ObservableObject {

    @Published var assets: [PhotoAsset] = []
    @Published var isLoading = false
    @Published var selectedCategory: PhotoCategory?

    private let photoService: PhotoLibraryService
    private let photoStore: PhotoStore
    private var cancellables = Set<AnyCancellable>()

    init(photoService: PhotoLibraryService, photoStore: PhotoStore) {
        self.photoService = photoService
        self.photoStore = photoStore

        // 监听授权状态变化，权限通过后自动加载照片
        photoService.$authorizationStatus
            .sink { [weak self] status in
                guard let self else { return }
                if status == .authorized || status == .limited {
                    Task { await self.loadPhotos() }
                }
            }
            .store(in: &cancellables)
    }

    func loadPhotos(searchText: String = "") async {
        guard photoService.authorizationStatus == .authorized ||
              photoService.authorizationStatus == .limited
        else { return }

        // 已有缓存数据时避免全屏 loading 遮挡网格
        let hasCachedAssets = !assets.isEmpty
        if !hasCachedAssets {
            isLoading = true
        }
        defer { isLoading = false }

        var allAssets = photoService.fetchAllAssets()
        var matchedIDs: Set<String>?

        if let category = selectedCategory {
            let records = photoStore.fetch(by: category)
            matchedIDs = Set(records.map(\.assetIdentifier))
        }

        if !searchText.isEmpty {
            let searchIDs = photoStore.searchIDs(query: searchText)
            matchedIDs = matchedIDs.map { $0.intersection(searchIDs) } ?? searchIDs
        }

        if let ids = matchedIDs {
            allAssets = allAssets.filter { ids.contains($0.localIdentifier) }
        }

        let targetSize = CGSize(width: 400, height: 400)
        var photoAssets: [PhotoAsset] = []

        for asset in allAssets {
            let thumbnail = await photoService.requestThumbnail(for: asset, targetSize: targetSize)
            let record = photoStore.fetch(by: asset.localIdentifier)
            photoAssets.append(PhotoAsset(asset: asset, thumbnail: thumbnail, record: record))
        }

        assets = photoAssets
    }

    func fetchRecord(for identifier: String) -> PhotoRecord? {
        photoStore.fetch(by: identifier)
    }
}
