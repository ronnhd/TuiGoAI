import Foundation

// MARK: - AI Models & Enums

public enum AIProviderType: String, CaseIterable, Codable, Sendable {
    case localOllama = "Local (Ollama)"
    case localMLX = "Local (MLX)"
    case openAI = "OpenAI"
    case custom = "Custom Endpoint"

    public var defaultBaseURL: String {
        switch self {
        case .localOllama:
            return "http://localhost:11434/v1"
        case .localMLX:
            return "http://localhost:8080/v1"
        case .openAI:
            return "https://api.openai.com/v1"
        case .custom:
            return "http://localhost:11434/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .localOllama:
            return "qwen2.5:latest"
        case .localMLX:
            return "default"
        case .openAI:
            return "gpt-4o-mini"
        case .custom:
            return "qwen2.5"
        }
    }
}

public enum AIRewriteTone: String, CaseIterable, Sendable {
    case formal = "Trang trọng"
    case casual = "Thân mật"
    case concise = "Ngắn gọn"
    case elaborate = "Mở rộng"

    var promptInstruction: String {
        switch self {
        case .formal:
            return "Viết lại đoạn văn bản sau bằng tiếng Việt với phong cách trang trọng, lịch sự, chuyên nghiệp trong công việc. Chỉ trả về kết quả đã viết lại, không thêm lời dẫn giải."
        case .casual:
            return "Viết lại đoạn văn bản sau bằng tiếng Việt với phong cách thân mật, tự nhiên, gần gũi trong giao tiếp hàng ngày. Chỉ trả về kết quả đã viết lại, không thêm lời dẫn giải."
        case .concise:
            return "Tóm tắt và viết lại đoạn văn bản sau ngắn gọn, súc tích, giữ nguyên ý chính và loại bỏ từ ngữ rườm rà. Chỉ trả về kết quả, không thêm lời dẫn giải."
        case .elaborate:
            return "Viết mở rộng và diễn giải mạch lạc đoạn văn bản sau, trau chuốt câu từ đầy đủ ngữ nghĩa. Chỉ trả về kết quả, không thêm lời dẫn giải."
        }
    }
}

public struct AIConfig: Codable, Sendable {
    public var isEnabled: Bool
    public var providerType: AIProviderType
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var temperature: Double
    public var timeoutInterval: TimeInterval

    public static let `default` = AIConfig(
        isEnabled: true,
        providerType: .localOllama,
        baseURL: AIProviderType.localOllama.defaultBaseURL,
        apiKey: "",
        model: AIProviderType.localOllama.defaultModel,
        temperature: 0.3,
        timeoutInterval: 15.0
    )
}

public enum AIError: LocalizedError, Sendable {
    case serviceDisabled
    case invalidURL
    case noResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .serviceDisabled:
            return "Tính năng AI đang tắt trong Cài đặt."
        case .invalidURL:
            return "Địa chỉ endpoint API không hợp lệ."
        case .noResponse:
            return "Không nhận được phản hồi từ mô hình AI."
        case let .httpError(statusCode, message):
            return "Lỗi máy chủ (\(statusCode)): \(message)"
        case let .decodingError(detail):
            return "Lỗi phân tích phản hồi: \(detail)"
        case let .networkError(detail):
            return "Lỗi kết nối: \(detail)"
        }
    }
}

// MARK: - OpenAI Compatible Payload Structs

private struct OpenAIChatRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool
}

private struct OpenAIChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String?
            let content: String?
        }

        let message: Message?
        let finish_reason: String?
    }

    let choices: [Choice]?
}

// MARK: - AIService Core Implementation

public final class AIService: @unchecked Sendable {
    public static let shared = AIService()

    private let configKey = "tuigoai.ai.config"
    private let urlSession: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15.0
        configuration.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Config Persistence

    public func loadConfig() -> AIConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(AIConfig.self, from: data)
        else {
            return .default
        }
        return config
    }

    public func saveConfig(_ config: AIConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    // MARK: - Low-level Completion Call

    public func complete(
        systemPrompt: String,
        userPrompt: String,
        overrideConfig: AIConfig? = nil
    ) async throws -> String {
        let config = overrideConfig ?? loadConfig()

        guard config.isEnabled else {
            throw AIError.serviceDisabled
        }

        var endpoint = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint.hasSuffix("/") {
            endpoint.removeLast()
        }

        let fullURLString: String
        if endpoint.hasSuffix("/chat/completions") {
            fullURLString = endpoint
        } else {
            fullURLString = "\(endpoint)/chat/completions"
        }

        guard let url = URL(string: fullURLString) else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let messages = [
            OpenAIChatRequest.Message(role: "system", content: systemPrompt),
            OpenAIChatRequest.Message(role: "user", content: userPrompt)
        ]

        let requestBody = OpenAIChatRequest(
            model: config.model,
            messages: messages,
            temperature: config.temperature,
            stream: false
        )

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw AIError.decodingError("Không thể đóng gói yêu cầu JSON.")
        }

        request.timeoutInterval = config.timeoutInterval

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.noResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw AIError.httpError(statusCode: httpResponse.statusCode, message: errorText)
        }

        do {
            let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            guard let content = chatResponse.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty
            else {
                throw AIError.noResponse
            }
            return content
        } catch {
            let rawString = String(data: data, encoding: .utf8) ?? ""
            throw AIError.decodingError("Lỗi đọc phản hồi JSON: \(error.localizedDescription). Phản hồi nhận được: \(rawString.prefix(100))")
        }
    }

    // MARK: - Feature 6: In-place Rewrite

    public func rewriteText(_ text: String, tone: AIRewriteTone) async throws -> String {
        let systemPrompt = "Bạn là trợ lý biên tập tiếng Việt cao cấp của bộ gõ TuiGoAI trên macOS. Nhiệm vụ của bạn là viết lại văn bản theo đúng phong cách yêu cầu, giữ nguyên ý nghĩa và thuật ngữ chuyên ngành."
        let userPrompt = """
        \(tone.promptInstruction)

        Văn bản gốc:
        \"\"\"
        \(text)
        \"\"\"
        """
        return try await complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
    }

    // MARK: - Feature 7: In-place Translation

    public func translateToEnglish(_ text: String, customGlossary: [String: String] = [:]) async throws -> String {
        var glossaryNote = ""
        if !customGlossary.isEmpty {
            glossaryNote = "Lưu ý giữ nguyên hoặc dịch chính xác các thuật ngữ / tên riêng sau:\n"
            for (vn, en) in customGlossary {
                glossaryNote += "- \(vn) -> \(en)\n"
            }
        }

        let systemPrompt = "Bạn là chuyên gia dịch thuật Việt - Anh chuyên nghiệp của bộ gõ TuiGoAI trên macOS. Dịch chính xác, tự nhiên, văn phong bản ngữ và giữ nguyên cấu trúc ngữ nghĩa."
        let userPrompt = """
        Dịch đoạn văn bản tiếng Việt sau sang tiếng Anh tự nhiên.
        \(glossaryNote)
        Chỉ trả về bản dịch tiếng Anh duy nhất, không thêm giải thích hay dấu ngoặc kép bọc ngoài.

        Văn bản gốc:
        \"\"\"
        \(text)
        \"\"\"
        """
        return try await complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
    }

    // MARK: - Feature 8: Pronoun & Tone Consistency Check

    public func checkPronounConsistency(_ text: String) async throws -> String? {
        let systemPrompt = "Bạn là trợ lý kiểm tra ngữ pháp và văn phong tiếng Việt của bộ gõ TuiGoAI. Nhiệm vụ của bạn là kiểm tra xem văn bản có bị lẫn lộn các đại từ xưng hô không (ví dụ: vừa xưng 'anh' vừa xưng 'bạn', vừa xưng 'mình' vừa xưng 'em' đối với cùng một đối tượng người nhận)."
        let userPrompt = """
        Hãy phân tích văn bản sau:
        - Nếu các cặp đại từ xưng hô nhất quán và tự nhiên, trả về đúng từ 'CONSISTENT'.
        - Nếu phát hiện xưng hô lộn xộn hoặc mâu thuẫn ngôi xưng, hãy nêu ngắn gọn trong 1 câu nhận xét (dưới 30 từ) và đề xuất cặp xưng hô nên dùng.

        Văn bản:
        \"\"\"
        \(text)
        \"\"\"
        """
        let result = try await complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
        if result.contains("CONSISTENT") {
            return nil
        }
        return result
    }

    // MARK: - Feature 9: Reverse Term Lookup

    public func reverseLookupTerm(_ description: String) async throws -> [String] {
        let systemPrompt = "Bạn là từ điển thuật ngữ thông minh cho bộ gõ TuiGoAI trên macOS. Người dùng mô tả khái niệm hoặc định nghĩa, bạn gợi ý các từ hoặc thuật ngữ tương ứng chính xác nhất."
        let userPrompt = """
        Dựa vào mô tả sau đây, hãy gợi ý tối đa 3 thuật ngữ sát nhất (kèm cả từ tiếng Anh hoặc tiếng Việt chuẩn nếu có).
        Định dạng trả về mỗi dòng 1 thuật ngữ duy nhất theo cấu trúc: [Thuật ngữ] - [Giải thích cực ngắn dưới 10 từ].
        Không trả lời chào hỏi.

        Mô tả:
        \"\"\"
        \(description)
        \"\"\"
        """
        let raw = try await complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Foundation Feature: Ghost Text Autocomplete

    public func suggestCompletion(prefixText: String) async throws -> String {
        let systemPrompt = "Bạn là mô hình autocomplete câu tiếng Việt tức thì của bộ gõ TuiGoAI. Nhiệm vụ: gợi ý phần tiếp theo rất ngắn gọn (từ 3 đến 8 từ) nối tiếp tự nhiên câu người dùng đang viết dở."
        let userPrompt = """
        Dựa vào đoạn văn bản đang viết dở sau đây, hãy viết tiếp một đoạn rất ngắn (3-8 từ) nối tiếp mạch văn:
        \"\"\"
        \(prefixText)
        \"\"\"

        Chỉ trả về đúng phần viết tiếp, không lặp lại đoạn gốc, không thêm dấu ngoặc kép hay giải thích.
        """
        return try await complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
    }
}
