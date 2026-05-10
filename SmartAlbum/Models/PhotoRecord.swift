import Foundation

/// 照片分析记录（纯 Codable struct，JSON 文件持久化）
struct PhotoRecord: Codable, Identifiable {
    /// PHAsset.localIdentifier，作为与系统相册的关联键
    var id: String { assetIdentifier }

    let assetIdentifier: String
    let creationDate: Date?
    var isAnalyzed: Bool

    /// 主分类（"人物"/"风景"/...）
    var primaryCategory: String?

    /// 标签 JSON 字符串
    private var tagsJSON: String?

    /// AI 生成的图片描述
    var imageDescription: String?

    /// 置信度 0-1
    var confidence: Double?

    /// 分析完成时间
    var analyzedAt: Date?

    // MARK: - Init

    init(
        assetIdentifier: String,
        creationDate: Date? = nil,
        isAnalyzed: Bool = false,
        primaryCategory: String? = nil,
        tags: [String] = [],
        imageDescription: String? = nil,
        confidence: Double? = nil,
        analyzedAt: Date? = nil
    ) {
        self.assetIdentifier = assetIdentifier
        self.creationDate = creationDate
        self.isAnalyzed = isAnalyzed
        self.primaryCategory = primaryCategory
        self.imageDescription = imageDescription
        self.confidence = confidence
        self.analyzedAt = analyzedAt
        self.tags = tags
    }

    // MARK: - 标签（JSON 编解码）

    var tags: [String] {
        get {
            guard let json = tagsJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                tagsJSON = String(data: data, encoding: .utf8)
            }
        }
    }

    /// 分类枚举
    var category: PhotoCategory? {
        get { primaryCategory.flatMap(PhotoCategory.init(rawValue:)) }
        set { primaryCategory = newValue?.rawValue }
    }
}
