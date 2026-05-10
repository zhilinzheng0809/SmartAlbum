import Foundation
import Combine

/// 照片分析记录持久化存储（内存 + JSON 文件）
@MainActor
final class PhotoStore: ObservableObject {

    @Published private(set) var records: [PhotoRecord] = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.smartalbum.store", qos: .utility)

    // MARK: - Init

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("smartalbum_records.json")
        load()
    }

    // MARK: - CRUD

    /// 插入或更新记录（按 assetIdentifier 去重）
    func upsert(_ record: PhotoRecord) {
        if let idx = records.firstIndex(where: { $0.assetIdentifier == record.assetIdentifier }) {
            records[idx] = record
        } else {
            records.append(record)
        }
        save()
    }

    /// 按 localIdentifier 查找
    func fetch(by identifier: String) -> PhotoRecord? {
        records.first { $0.assetIdentifier == identifier }
    }

    /// 获取全部记录
    func fetchAll() -> [PhotoRecord] {
        records
    }

    /// 获取已分析的 assetIdentifier 集合
    func fetchAnalyzedIDs() -> Set<String> {
        Set(records.lazy.filter(\.isAnalyzed).map(\.assetIdentifier))
    }

    /// 按分类获取记录
    func fetch(by category: PhotoCategory) -> [PhotoRecord] {
        records.filter { $0.primaryCategory == category.rawValue }
    }

    /// 全局关键词搜索（标签 + 描述 + 分类）
    func search(query: String) -> [PhotoRecord] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        return records.filter { record in
            record.tags.contains { $0.localizedCaseInsensitiveContains(q) } ||
            record.imageDescription?.localizedCaseInsensitiveContains(q) == true ||
            record.primaryCategory?.localizedCaseInsensitiveContains(q) == true
        }
    }

    /// 模糊搜索返回 assetIdentifier 集合
    func searchIDs(query: String) -> Set<String> {
        Set(search(query: query).map(\.assetIdentifier))
    }

    /// 删除记录
    func delete(by identifier: String) {
        records.removeAll { $0.assetIdentifier == identifier }
        save()
    }

    // MARK: - Persistence

    private func save() {
        let snapshot = records
        queue.async { [fileURL] in
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                print("[PhotoStore] 保存失败: \(error.localizedDescription)")
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder().decode([PhotoRecord].self, from: data)
        } catch {
            print("[PhotoStore] 加载失败: \(error.localizedDescription)")
            records = []
        }
    }
}
