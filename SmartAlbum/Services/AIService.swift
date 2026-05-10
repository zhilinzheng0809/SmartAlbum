import Foundation

// MARK: - AI 分析响应模型

/// AI 返回的结构化分析结果
struct AIAnalysisResponse: Codable {
    let primaryCategory: String
    let tags: [String]
    let description: String
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case primaryCategory = "primary_category"
        case tags
        case description
        case confidence
    }
}

// MARK: - OpenAI 兼容 API 响应模型

private struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - AI 服务

/// OpenAI 兼容的 Vision API 客户端（已适配通义千问）
final class AIService {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    /// 调用 Vision API 对图片进行分析
    func analyzeImage(
        imageData: Data,
        apiKey: String,
        endpoint: String,
        model: String
    ) async throws -> AIAnalysisResponse {

        let base64Image = imageData.base64EncodedString()
        let dataURI = "data:image/jpeg;base64,\(base64Image)"

        // 通义千问兼容模式不支持 response_format json_object，
        // 通过 system prompt 约束输出格式
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": Self.systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": ["url": dataURI]
                        ]
                    ]
                ]
            ],
            "max_tokens": 500,
            "temperature": 0.1
        ]

        var request = URLRequest(url: URL(string: "\(endpoint)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(httpResponse.statusCode, body)
        }

        let decoder = JSONDecoder()
        let chatResponse = try decoder.decode(ChatCompletionResponse.self, from: data)

        guard let rawContent = chatResponse.choices.first?.message.content else {
            throw AIError.noContent
        }

        // 提取 JSON（兼容通义千问可能输出 markdown 包裹的 JSON）
        let jsonString = Self.extractJSON(from: rawContent)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIError.noContent
        }

        do {
            return try decoder.decode(AIAnalysisResponse.self, from: jsonData)
        } catch {
            throw AIError.decodeFailed(rawContent)
        }
    }

    // MARK: - System Prompt

    private static let systemPrompt = """
    你是一个专业的图片分类助手。请分析这张图片，并以严格的JSON格式返回结果。
    注意：你的整个回复必须只包含JSON本身，不要有任何解释、前言、后缀或markdown标记。

    【分类选项】（必须选择最匹配的一项，使用中文）：
    - 人物：人像、自拍、合影、个人照
    - 风景：自然风光、山水、日落、海滩、星空
    - 食物：美食、饮品、烹饪、甜点
    - 动物：宠物、野生动物、昆虫
    - 文档截图：屏幕截图、文档、二维码、表格、代码
    - 艺术设计：绘画、设计稿、海报、插画
    - 建筑：室内外建筑、城市景观、街景
    - 植物：花卉、树木、绿植
    - 交通工具：汽车、自行车、飞机、船舶
    - 其他：无法归入以上类别

    返回示例：
    {"primary_category":"风景","tags":["日落","海滩","晚霞"],"description":"海边的日落景色","confidence":0.95}

    要求：
    - primary_category 必须是上述十个选项之一
    - tags 包含3-5个具体的中文描述性标签
    - description 为20字以内的简短描述
    - confidence 为置信度 0-1
    - 整个回复就是这一行JSON，不要有任何额外内容
    """
}

// MARK: - JSON 提取

extension AIService {

    /// 从 LLM 原始回复中提取 JSON 字符串
    /// 兼容以下情况：
    /// - 纯 JSON：{"primary_category": ...}
    /// - Markdown 包裹：```json\n{...}\n```
    /// - 带前导文字：这里是分析结果：{"primary_category": ...}
    static func extractJSON(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 尝试从 markdown 代码块中提取
        let mdPattern = try? NSRegularExpression(pattern: "```(?:json)?\\s*\\n?([\\s\\S]*?)\\n?```", options: [])
        if let match = mdPattern?.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
           let range = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 查找第一个 { 到最后一个 } 之间的内容
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }

        // 兜底返回原文
        return trimmed
    }
}

// MARK: - 错误定义

extension AIService {
    enum AIError: LocalizedError {
        case httpError(Int, String)
        case noContent
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .httpError(let code, let body):
                return "API 返回错误 (HTTP \(code)): \(body)"
            case .noContent:
                return "AI 未返回有效内容"
            case .decodeFailed(let detail):
                return "结果解析失败: \(detail)"
            }
        }
    }
}
