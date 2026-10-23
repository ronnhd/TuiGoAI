import AppKit
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
        model: "qwen2.5:3b",
        temperature: 0.1,
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

    /// Danh sách các từ đơn tiếng Việt có thể láy toàn phần hợp lệ (tối đa 2 lần liên tiếp).
    private static let vietnameseReduplicableWords: Set<String> = [
        "luôn", "từ", "đều", "nhanh", "chầm", "chậm", "dần", "sớm", "chiều",
        "ngày", "đêm", "tháng", "năm", "đời", "người", "nhà", "hơi", "rất",
        "nhỏ", "to", "cao", "thấp", "xa", "gần", "lâu", "mãi", "vừa", "cùng",
        "từng", "mỗi", "ai", "gì", "đâu", "nào", "sao", "thế", "vậy", "ừ", "vâng",
    ]

    /// Các cụm mở đầu câu trả lời hội thoại lệch vai (khi model trả lời câu hỏi thay vì viết tiếp câu đang gõ).
    private static let conversationalReplyPrefixes: [String] = [
        "dạ vâng", "vâng ạ", "chào bạn", "xin chào", "tôi có thể giúp",
        "bạn cần hỗ trợ", "mình có thể giúp", "dưới đây là", "câu trả lời là",
    ]

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15.0
        configuration.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Config Persistence

    public func loadConfig() -> AIConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              var config = try? JSONDecoder().decode(AIConfig.self, from: data)
        else {
            return .default
        }
        config.providerType = .localOllama
        config.baseURL = AIProviderType.localOllama.defaultBaseURL
        config.apiKey = ""
        if config.model == "qwen2.5:latest" || config.model.isEmpty {
            config.model = "qwen2.5:3b"
        }
        return config
    }

    public func saveConfig(_ config: AIConfig) {
        var localConfig = config
        localConfig.providerType = .localOllama
        localConfig.baseURL = AIProviderType.localOllama.defaultBaseURL
        localConfig.apiKey = ""
        if let data = try? JSONEncoder().encode(localConfig) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    public func setAIEnabled(_ enabled: Bool) {
        var config = loadConfig()
        config.isEnabled = enabled
        config.providerType = .localOllama
        saveConfig(config)
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
            return content.precomposedStringWithCanonicalMapping
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
        \(text.precomposedStringWithCanonicalMapping)
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
        \(text.precomposedStringWithCanonicalMapping)
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
        \(text.precomposedStringWithCanonicalMapping)
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
        \(description.precomposedStringWithCanonicalMapping)
        \"\"\"
        """
        let raw = try await complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Feature: FixNow in-place correction

    public func fixSpelling(_ text: String) async throws -> String {
        let config = loadConfig()
        guard config.isEnabled else { throw AIError.serviceDisabled }
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw AIError.noResponse }

        let endpoint = URL(string: "http://localhost:11434/api/generate")!
        let prompt = """
        <|im_start|>system
        \(FixNowManager.fixSystemPrompt)<|im_end|>
        <|im_start|>user
        \(FixNowManager.buildFixUserPrompt(text))<|im_end|>
        <|im_start|>assistant

        """
        let payload = OllamaGenerateRequest(
            model: model,
            prompt: prompt,
            raw: true,
            stream: false,
            options: OllamaGenerateRequest.Options(
                temperature: 0.1,
                topP: 0.8,
                topK: 20,
                repeatPenalty: 1.0,
                numPredict: text.count + 100,
                stop: ["<|im_end|>", "<|endoftext|>"]
            ),
            keepAlive: "5m"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AIError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw AIError.noResponse }
        guard (200 ... 299).contains(http.statusCode) else {
            throw AIError.httpError(statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "Ollama error")
        }
        let result = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        guard let raw = result.response, !raw.isEmpty else { throw AIError.noResponse }
        return raw.precomposedStringWithCanonicalMapping
    }

    // MARK: - Foundation Feature: Ghost Text Autocomplete

    public func suggestCompletion(
        prefixText: String,
        suffixText: String = "",
        appName: String? = nil,
        bundleId: String? = nil
    ) async throws -> String {
        let config = loadConfig()
        guard config.isEnabled else { throw AIError.serviceDisabled }
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw AIError.noResponse }

        let lengthRaw = UserDefaults.standard.string(forKey: GhostTextManager.completionLengthKey) ?? "medium"
        let lengthConfig = GhostTextCompletionLength(rawValue: lengthRaw) ?? .medium

        let nfcPrefix = prefixText.precomposedStringWithCanonicalMapping
        let nfcSuffix = suffixText.precomposedStringWithCanonicalMapping

        let trimmedPrefix = CaretBoundary.trimmingTrailingWhitespace(nfcPrefix)
        guard !trimmedPrefix.isEmpty else { throw AIError.noResponse }
        let windowedPrefix = String(trimmedPrefix.suffix(2000))
        let windowedSuffix = String(nfcSuffix.prefix(500)).trimmingCharacters(in: .newlines)

        var recentMessages: [String] = []
        if let bundle = bundleId {
            recentMessages = ChatHistoryBuffer.shared.recentHistory(for: bundle)
        }
        let clipboard = Self.safeClipboardText()
        let promptText = Self.buildAutocompletePrompt(
            prefix: windowedPrefix,
            suffix: windowedSuffix,
            recentMessages: recentMessages,
            appName: appName,
            clipboardText: clipboard
        )

        let endpoint = URL(string: "http://localhost:11434/api/generate")!
        let payload = OllamaGenerateRequest(
            model: model,
            prompt: promptText,
            raw: true,
            stream: false,
            options: OllamaGenerateRequest.Options(
                temperature: 0.1,
                topP: 0.8,
                topK: 20,
                repeatPenalty: 1.15,
                numPredict: lengthConfig.numPredict,
                stop: ["\n", "\r", "<|im_end|>", "<|endoftext|>", "```"]
            ),
            keepAlive: "5m"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = min(max(config.timeoutInterval, 5), 30)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AIError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw AIError.noResponse }
        guard (200 ... 299).contains(http.statusCode) else {
            throw AIError.httpError(statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "Ollama error")
        }
        let result = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        guard let raw = result.response, !raw.isEmpty else { throw AIError.noResponse }
        let cleaned = Self.cleanCompletion(raw, prefix: nfcPrefix, suffix: nfcSuffix, maxWords: lengthConfig.maxWords)
        guard !cleaned.isEmpty else { throw AIError.noResponse }
        return cleaned
    }

    /// Trích xuất nội dung Clipboard an toàn dùng làm ngữ cảnh gợi ý (liên kết, tên, địa chỉ, mã số)
    public static func safeClipboardText() -> String? {
        if UserDefaults.standard.object(forKey: GhostTextManager.clipboardContextEnabledKey) != nil {
            guard UserDefaults.standard.bool(forKey: GhostTextManager.clipboardContextEnabledKey) else {
                return nil
            }
        }
        guard let raw = NSPasteboard.general.string(forType: .string) else { return nil }
        let trimmed = raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        // Giới hạn chiều dài: từ 4 đến 300 ký tự
        guard trimmed.count >= 4, trimmed.count <= 300 else { return nil }
        // Giới hạn dòng: tối đa 3 dòng (tránh paste cả văn bản dài)
        guard trimmed.components(separatedBy: .newlines).count <= 3 else { return nil }
        // Bộ lọc an toàn: bỏ qua chuỗi trông giống secret/token
        if trimmed.hasPrefix("sk-") || trimmed.hasPrefix("ghp_") || trimmed.hasPrefix("eyJh") {
            return nil
        }
        return trimmed
    }

    public static func buildAutocompletePrompt(
        prefix: String,
        suffix: String = "",
        recentMessages: [String] = [],
        appName: String? = nil,
        clipboardText: String? = nil
    ) -> String {
        let nfcPrefix = prefix.precomposedStringWithCanonicalMapping
        let trimmedPrefix = CaretBoundary.trimmingTrailingWhitespace(nfcPrefix)
        guard !trimmedPrefix.isEmpty else { return "" }
        let trimmedSuffix = suffix.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)

        var userLines: [String] = []
        let history = recentMessages
            .map { $0.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(3)
        if !history.isEmpty {
            userLines.append("Các câu người dùng vừa viết gần đây:")
            for msg in history {
                userLines.append("- \(msg)")
            }
        }
        if let clip = clipboardText?.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty, clip != trimmedPrefix {
            userLines.append("Nội dung vừa sao chép (tham khảo nếu liên quan):")
            userLines.append(clip)
        }
        if !trimmedSuffix.isEmpty {
            userLines.append("Đoạn văn tiếp theo ngay sau con trỏ (tránh lặp lại):")
            userLines.append(trimmedSuffix)
            userLines.append("Viết tiếp phần nối ở giữa câu bằng tiếng Việt:")
        } else {
            userLines.append("Viết tiếp câu đang gõ bằng tiếng Việt:")
        }
        let userContent = userLines.joined(separator: "\n")

        return """
        <|im_start|>system
        Bạn là bộ gõ tiếng Việt. Bạn chỉ viết tiếp phần còn thiếu của câu người dùng đang gõ bằng tiếng Việt tự nhiên (chữ Quốc ngữ). Tuyệt đối không trả lời câu hỏi, không giải thích, không dùng tiếng nước ngoài, không lặp lại từ đã có. Giữ đúng phong cách và xưng hô của người dùng.<|im_end|>
        <|im_start|>user
        \(userContent)<|im_end|>
        <|im_start|>assistant
        \(trimmedPrefix)
        """
    }

    static func stripOverlappingPrefix(_ text: String, prefix: String) -> String {
        let result = text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .newlines)
        let nfcPrefix = prefix.precomposedStringWithCanonicalMapping
        let trimmedPrefix = nfcPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrefix.isEmpty, !result.isEmpty else { return result }

        if result.hasPrefix(trimmedPrefix) {
            return String(result.dropFirst(trimmedPrefix.count))
        }
        let lowerPrefix = trimmedPrefix.lowercased()
        let lowerResult = result.lowercased()
        if lowerResult.hasPrefix(lowerPrefix) {
            return String(result.dropFirst(trimmedPrefix.count))
        }

        let prefixWords = trimmedPrefix.split(whereSeparator: \.isWhitespace).map(String.init)
        let resultWords = result.split(whereSeparator: \.isWhitespace).map(String.init)
        let maxOverlap = min(prefixWords.count, resultWords.count)
        guard maxOverlap >= 1 else { return result }

        for count in stride(from: maxOverlap, through: 1, by: -1) {
            let suffix = Array(prefixWords.suffix(count))
            let head = Array(resultWords.prefix(count))
            let matched = zip(suffix, head).allSatisfy { left, right in
                left.trimmingCharacters(in: .punctuationCharacters)
                    .localizedCaseInsensitiveCompare(
                        right.trimmingCharacters(in: .punctuationCharacters)
                    ) == .orderedSame
            }
            if matched {
                if count == 1, let singleWord = head.first {
                    let normWord = singleWord.trimmingCharacters(in: .punctuationCharacters).lowercased()
                    let alreadyDoubledInPrefix: Bool = {
                        guard prefixWords.count >= 2 else { return false }
                        let secondLast = prefixWords[prefixWords.count - 2]
                            .trimmingCharacters(in: .punctuationCharacters).lowercased()
                        return secondLast == normWord
                    }()
                    if vietnameseReduplicableWords.contains(normWord) && !alreadyDoubledInPrefix && resultWords.count >= 2 {
                        break
                    }
                }
                return resultWords.dropFirst(count).joined(separator: " ")
            }
        }

        // Nếu con trỏ đang dừng ở phụ âm đầu tiếng Việt chưa hoàn chỉnh (vd: "chương tr")
        // và từ đầu tiên của model lặp lại phụ âm đầu đó để hoàn thành âm tiết (vd: "trình mới"),
        // cắt bỏ phần phụ âm đầu trùng lặp để giữ lại phần vần ("ình mới").
        if CaretBoundary.hasUnfinishedTrailingSyllable(nfcPrefix),
           let lastOnset = prefixWords.last?.lowercased(),
           let firstWord = resultWords.first {
            let lowerFirst = firstWord.lowercased()
            if lowerFirst.hasPrefix(lastOnset), lowerFirst.count > lastOnset.count {
                let remainderStart = firstWord.index(firstWord.startIndex, offsetBy: lastOnset.count)
                let remainder = String(firstWord[remainderStart...])
                if let firstRemainderChar = remainder.first, CaretBoundary.isVietnameseVowel(firstRemainderChar) {
                    let tailWords = resultWords.dropFirst()
                    if tailWords.isEmpty {
                        return remainder
                    }
                    return ([remainder] + tailWords).joined(separator: " ")
                }
            }
        }

        return result
    }

    /// Khử các cụm từ ghép tiếng Việt (2–3 âm tiết) bị lặp liên tiếp do LLM nhỏ bị loop.
    static func collapseRepeatedNGrams(_ words: [String]) -> [String] {
        guard words.count >= 4 else { return words }
        var current = words
        for n in [3, 2] {
            var output: [String] = []
            var i = 0
            while i < current.count {
                if output.count >= n && i + n <= current.count {
                    let prevNGram = output.suffix(n).map {
                        $0.trimmingCharacters(in: .punctuationCharacters).lowercased()
                    }
                    let nextNGram = current[i ..< (i + n)].map {
                        $0.trimmingCharacters(in: .punctuationCharacters).lowercased()
                    }
                    if prevNGram == nextNGram {
                        i += n
                        continue
                    }
                }
                output.append(current[i])
                i += 1
            }
            current = output
        }
        return current
    }

    static func cleanCompletion(_ raw: String, prefix: String, suffix: String, maxWords: Int = 8) -> String {
        let nfcPrefix = prefix.precomposedStringWithCanonicalMapping
        let nfcSuffix = suffix.precomposedStringWithCanonicalMapping
        var text = raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .newlines)
        text = text.replacingOccurrences(of: "^```[^\\n]*\\n|\\n```$", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\\\"'`"))
        guard !text.isEmpty else { return "" }

        // Strip foreign script hallucinations (CJK, Hangul, Katakana, Hiragana)
        let hasForbiddenScript = text.unicodeScalars.contains { scalar in
            (0x4E00 ... 0x9FFF).contains(scalar.value) || // CJK Unified Ideographs
            (0x3400 ... 0x4DBF).contains(scalar.value) || // CJK Extension A
            (0xAC00 ... 0xD7AF).contains(scalar.value) || // Hangul Syllables
            (0x3040 ... 0x30FF).contains(scalar.value)    // Hiragana / Katakana
        }
        if hasForbiddenScript {
            return ""
        }

        text = stripOverlappingPrefix(text, prefix: nfcPrefix)
        guard !text.isEmpty else { return "" }

        // Suffix overlap guard
        if !nfcSuffix.isEmpty {
            if SuffixOverlapGuard.duplicatesSuffix(completion: text.trimmingCharacters(in: .whitespaces), beforeCursor: nfcPrefix, afterCursor: nfcSuffix) {
                if let nonDupLen = SuffixOverlapGuard.nonDuplicatingPrefixLength(completion: text.trimmingCharacters(in: .whitespaces), beforeCursor: nfcPrefix, afterCursor: nfcSuffix), nonDupLen > 0 {
                    text = String(text.prefix(nonDupLen))
                } else {
                    return ""
                }
            }
        }
        guard !text.isEmpty else { return "" }

        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        var words = firstLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return "" }

        // Chặn trường hợp model đóng vai người trả lời câu hỏi thay vì viết tiếp câu của người dùng
        let prefixWords = nfcPrefix.split(whereSeparator: \.isWhitespace).map(String.init)
        if prefixWords.count >= 2 {
            let candidateLower = words.prefix(4).joined(separator: " ").lowercased()
            if conversationalReplyPrefixes.contains(where: { candidateLower.hasPrefix($0) }) {
                return ""
            }
        }

        // Xử lý từ đầu gợi ý trùng với từ cuối của prefix:
        // Giữ lại nếu là từ láy toàn phần tiếng Việt hợp lệ (vd: prefix "cứ từ " + "từ thôi nhé" -> "cứ từ từ thôi nhé"),
        // nhưng loại bỏ nếu không phải từ láy hoặc trong prefix đã lặp đôi sẵn.
        if let lastPrefixWord = prefixWords.last,
           let firstWord = words.first {
            let normLast = lastPrefixWord.trimmingCharacters(in: .punctuationCharacters).lowercased()
            let normFirst = firstWord.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if normLast == normFirst {
                let alreadyDoubledInPrefix: Bool = {
                    guard prefixWords.count >= 2 else { return false }
                    let secondLast = prefixWords[prefixWords.count - 2]
                        .trimmingCharacters(in: .punctuationCharacters).lowercased()
                    return secondLast == normLast
                }()
                let canReduplicate = vietnameseReduplicableWords.contains(normFirst) && !alreadyDoubledInPrefix && words.count >= 2
                if !canReduplicate {
                    words.removeFirst()
                }
            }
        }
        guard !words.isEmpty else { return "" }

        // Khử lặp từ đơn nhưng bảo toàn từ láy toàn phần tiếng Việt (cho phép lặp tối đa 2 lần)
        var deduplicated: [String] = []
        for word in words {
            let normWord = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if let last = deduplicated.last {
                let normLast = last.trimmingCharacters(in: .punctuationCharacters).lowercased()
                if normLast == normWord {
                    let isReduplicable = vietnameseReduplicableWords.contains(normWord)
                    let alreadyRepeatedTwice: Bool = {
                        guard deduplicated.count >= 2 else { return false }
                        let secondLast = deduplicated[deduplicated.count - 2]
                            .trimmingCharacters(in: .punctuationCharacters).lowercased()
                        return secondLast == normWord
                    }()
                    if !isReduplicable || alreadyRepeatedTwice {
                        continue
                    }
                }
            }
            deduplicated.append(word)
        }

        // Khử lặp cụm 2–3 âm tiết liên tiếp (vd: "kế hoạch kế hoạch", "cho dự án cho dự án")
        let nGramCleaned = collapseRepeatedNGrams(deduplicated)
        let joined = nGramCleaned.prefix(maxWords).joined(separator: " ")
        guard !joined.isEmpty else { return "" }
        return CaretBoundary.reconcile(joined, beforeCursor: nfcPrefix)
    }

    private struct OllamaGenerateRequest: Encodable {
        struct Options: Encodable {
            let temperature: Double
            let topP: Double?
            let topK: Int?
            let repeatPenalty: Double?
            let numPredict: Int
            let stop: [String]
            enum CodingKeys: String, CodingKey {
                case temperature
                case topP = "top_p"
                case topK = "top_k"
                case repeatPenalty = "repeat_penalty"
                case numPredict = "num_predict"
                case stop
            }
        }
        let model: String
        let prompt: String
        let raw: Bool
        let stream: Bool
        let options: Options
        let keepAlive: String
        enum CodingKeys: String, CodingKey {
            case model, prompt, raw, stream, options
            case keepAlive = "keep_alive"
        }
    }

    private struct OllamaGenerateResponse: Decodable {
        let response: String?
    }
}
