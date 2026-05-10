import Foundation
import Combine
import Photos
import UIKit

/// 系统相册访问服务，封装 Photos.framework 的授权与资源读取
@MainActor
final class PhotoLibraryService: ObservableObject {

    /// 当前授权状态
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    // MARK: - 权限

    /// 请求相册读写权限
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status
    }

    // MARK: - 资源获取

    /// 获取全部图片 Asset（按创建时间倒序）
    func fetchAllAssets() -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.image.rawValue
        )

        let result = PHAsset.fetchAssets(with: fetchOptions)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    /// 获取指定 localIdentifier 的 Asset
    func fetchAsset(by identifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        )
        return result.firstObject
    }

    // MARK: - 缩略图

    /// 异步请求缩略图
    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - 高清图（详情页使用）

    /// 异步请求高清图片（供详情页展示）
    /// 使用有限目标尺寸避免触发 iCloud 原图下载，兼容云端照片缺失场景
    func requestFullImage(for asset: PHAsset) async -> UIImage? {
        // 以设备屏幕尺寸 × 2 作为目标，确保 Retina 屏清晰同时避免请求原图
        let scale = UIScreen.main.scale
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(width: screenSize.width * scale, height: screenSize.height * scale)

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - 原图数据

    /// 异步请求原图 Data（供AI分析使用）
    func requestFullImageData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            var resumed = false
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: data)
            }
        }
    }
}
