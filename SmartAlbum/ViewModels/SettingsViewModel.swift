import Foundation
import Combine

/// 设置页 ViewModel：管理 API 配置持久化
@MainActor
final class SettingsViewModel: ObservableObject {

    @Published var apiKey: String = "sk-f455a0248cd540bca5c78a9ab895be98"
    @Published var endpoint: String = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    @Published var model: String = "qwen-vl-max"

    private enum Key {
        static let apiKey = "smartalbum_api_key"
        static let endpoint = "smartalbum_endpoint"
        static let model = "smartalbum_model"
    }

    init() {
        loadSettings()
    }

    func loadSettings() {
        apiKey = UserDefaults.standard.string(forKey: Key.apiKey) ?? "sk-f455a0248cd540bca5c78a9ab895be98"
        endpoint = UserDefaults.standard.string(forKey: Key.endpoint) ?? "https://dashscope.aliyuncs.com/compatible-mode/v1"
        model = UserDefaults.standard.string(forKey: Key.model) ?? "qwen-vl-max"
    }

    func saveSettings() {
        UserDefaults.standard.set(apiKey, forKey: Key.apiKey)
        UserDefaults.standard.set(endpoint, forKey: Key.endpoint)
        UserDefaults.standard.set(model, forKey: Key.model)
    }

    /// 是否已完成 AI 配置
    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !endpoint.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
