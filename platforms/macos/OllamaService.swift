import Foundation

public struct OllamaModelInfo: Codable, Identifiable, Sendable {
    public let name: String
    public let size: Int64?
    public let modifiedAt: String?

    public var id: String { name }
    public var sizeDescription: String {
        guard let size, size > 0 else { return "Chưa rõ dung lượng" }
        let gigabytes = Double(size) / 1_000_000_000
        return String(format: "%.1f GB", gigabytes)
    }
}

public struct OllamaModelRecommendation: Identifiable, Sendable {
    public let id: String
    public let model: String
    public let title: String
    public let description: String
    public let memoryRequirement: String
    public let minimumMemoryGB: Int

    public init(model: String, title: String, description: String, memoryRequirement: String, minimumMemoryGB: Int) {
        self.id = model
        self.model = model
        self.title = title
        self.description = description
        self.memoryRequirement = memoryRequirement
        self.minimumMemoryGB = minimumMemoryGB
    }
}

@MainActor
public final class OllamaService: ObservableObject {
    public static let shared = OllamaService()

    @Published public private(set) var isReachable = false
    @Published public private(set) var models: [OllamaModelInfo] = []
    @Published public private(set) var downloadingModel: String?
    @Published public private(set) var downloadProgress: Double?
    @Published public private(set) var errorMessage: String?

    public let recommendations: [OllamaModelRecommendation] = [
        OllamaModelRecommendation(
            model: "qwen2.5:1.5b",
            title: "Nhẹ và nhanh",
            description: "Phù hợp để thử autocomplete trên máy 8 GB RAM.",
            memoryRequirement: "Khoảng 1 GB",
            minimumMemoryGB: 8
        ),
        OllamaModelRecommendation(
            model: "qwen2.5:3b",
            title: "Cân bằng",
            description: "Lựa chọn mặc định cho máy 16 GB, ưu tiên chất lượng tiếng Việt.",
            memoryRequirement: "Khoảng 2.5 GB",
            minimumMemoryGB: 16
        ),
        OllamaModelRecommendation(
            model: "qwen2.5:7b",
            title: "Chất lượng cao hơn",
            description: "Gợi ý tốt hơn nhưng cần nhiều RAM và có thể chậm hơn.",
            memoryRequirement: "Khoảng 5 GB",
            minimumMemoryGB: 16
        ),
    ]

    private let baseURL = URL(string: "http://localhost:11434")!
    private var pullTask: Task<Void, Never>?

    private init() {}

    public func refresh() async {
        errorMessage = nil
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
            request.timeoutInterval = 2
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                throw OllamaError.unreachable
            }
            let payload = try JSONDecoder().decode(TagsResponse.self, from: data)
            models = payload.models.map {
                OllamaModelInfo(name: $0.name, size: $0.size, modifiedAt: $0.modifiedAt)
            }.sorted { $0.name < $1.name }
            isReachable = true
        } catch {
            isReachable = false
            models = []
            errorMessage = "Không kết nối được Ollama tại localhost:11434."
        }
    }

    public func pull(model: String) {
        guard downloadingModel == nil else { return }
        pullTask?.cancel()
        downloadingModel = model
        downloadProgress = nil
        errorMessage = nil
        pullTask = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(PullRequest(name: model, stream: true))
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    throw OllamaError.unreachable
                }
                for try await line in bytes.lines {
                    guard !Task.isCancelled, let data = line.data(using: .utf8),
                          let update = try? JSONDecoder().decode(PullUpdate.self, from: data)
                    else { continue }
                    if let total = update.total, total > 0, let completed = update.completed {
                        downloadProgress = Double(completed) / Double(total)
                    }
                }
                await refresh()
            } catch is CancellationError {
                // User cancellation leaves the daemon state untouched.
            } catch {
                errorMessage = "Tải model thất bại. Kiểm tra Ollama rồi thử lại."
            }
            downloadingModel = nil
            downloadProgress = nil
        }
    }

    public func delete(model: String) async {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/delete"))
            request.httpMethod = "DELETE"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["name": model])
            _ = try await URLSession.shared.data(for: request)
            await refresh()
        } catch {
            errorMessage = "Không xóa được model \(model)."
        }
    }

    public func cancelPull() {
        pullTask?.cancel()
        pullTask = nil
        downloadingModel = nil
        downloadProgress = nil
    }
    public func hasModel(_ name: String) -> Bool {
        models.contains { $0.name == name }
    }

    private struct TagsResponse: Decodable {
        let models: [TagModel]
    }

    private struct TagModel: Decodable {
        let name: String
        let size: Int64?
        let modifiedAt: String?
        enum CodingKeys: String, CodingKey {
            case name, size
            case modifiedAt = "modified_at"
        }
    }

    private struct PullRequest: Encodable {
        let name: String
        let stream: Bool
    }

    private struct PullUpdate: Decodable {
        let total: Int64?
        let completed: Int64?
    }
}

private enum OllamaError: Error {
    case unreachable
}
