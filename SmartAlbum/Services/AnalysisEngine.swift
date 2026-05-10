import Foundation
import Combine
import Photos
import UIKit

/// 批量分析调度引擎：遍历未分析照片 → 压缩 → 调AI → 入库
@MainActor
final class AnalysisEngine: ObservableObject {

    // MARK: - 发布的状态

    @Published var isAnalyzing = false
    @Published var totalCount = 0
    @Published var analyzedCount = 0
    @Published var currentError: String?

    // MARK: - 依赖

    private let photoService: PhotoLibraryService
    private let aiService: AIService
    private let photoStore: PhotoStore

    init(
        photoService: PhotoLibraryService,
        aiService: AIService,
        photoStore: PhotoStore
    ) {
        self.photoService = photoService
        self.aiService = aiService
        self.photoStore = photoStore
    }

    // MARK: - 批量分析

    /// 批量分析所有未分析的照片
    func analyzeNewPhotos(
        apiKey: String,
        endpoint: String,
        model: String
    ) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        totalCount = 0
        analyzedCount = 0
        currentError = nil
        defer { isAnalyzing = false }

        let allAssets = photoService.fetchAllAssets()
        let analyzedIDs = photoStore.fetchAnalyzedIDs()
        let newAssets = allAssets.filter { !analyzedIDs.contains($0.localIdentifier) }

        totalCount = newAssets.count
        guard totalCount > 0 else { return }

        for asset in newAssets {
            guard isAnalyzing else { break }

            do {
                try await analyzeSingle(asset, apiKey: apiKey, endpoint: endpoint, model: model)
                analyzedCount += 1
            } catch {
                currentError = error.localizedDescription
            }

            try? await Task.sleep(nanoseconds: 800_000_000)
        }
    }

    /// 分析单张照片（供详情页手动触发）
    func analyzeSingle(
        _ asset: PHAsset,
        apiKey: String,
        endpoint: String,
        model: String
    ) async throws {
        guard photoStore.fetch(by: asset.localIdentifier)?.isAnalyzed != true else { return }

        guard let imageData = await photoService.requestFullImageData(for: asset),
              let compressed = compressImage(imageData)
        else {
            throw EngineError.imageProcessingFailed
        }

        let result = try await aiService.analyzeImage(
            imageData: compressed,
            apiKey: apiKey,
            endpoint: endpoint,
            model: model
        )

        var record = PhotoRecord(
            assetIdentifier: asset.localIdentifier,
            creationDate: asset.creationDate,
            isAnalyzed: true,
            imageDescription: result.description,
            confidence: result.confidence,
            analyzedAt: Date()
        )
        record.category = PhotoCategory(rawValue: result.primaryCategory) ?? .other
        record.tags = result.tags

        photoStore.upsert(record)
    }

    // MARK: - Private

    private func compressImage(_ data: Data, maxDimension: CGFloat = 1024) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)

        guard scale < 1.0 else {
            return image.jpegData(compressionQuality: 0.8)
        }

        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        return resized?.jpegData(compressionQuality: 0.8)
    }
}

extension AnalysisEngine {
    enum EngineError: LocalizedError {
        case imageProcessingFailed
        var errorDescription: String? {
            switch self {
            case .imageProcessingFailed: return "图片处理失败"
            }
        }
    }
}
