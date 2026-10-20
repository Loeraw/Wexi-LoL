import Combine
import Foundation
import Security

private enum AIKeychain {
    static let service = "dev.local.wexilol.ai-review"
    static let account = "api-key"

    static func read() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ value: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return true }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

private struct AIServiceError: Decodable {
    struct Detail: Decodable { let message: String? }
    let error: Detail?
}

@MainActor final class AIReviewStore: ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }
    @Published var apiURL: String {
        didSet { UserDefaults.standard.set(apiURL, forKey: Self.urlKey) }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelKey) }
    }
    @Published var apiKeyDraft: String
    @Published private(set) var hasSavedKey: Bool
    @Published private(set) var advice = ""
    @Published private(set) var status = ""
    @Published private(set) var isGenerating = false

    private static let enabledKey = "aiReview.enabled"
    private static let urlKey = "aiReview.apiURL"
    private static let modelKey = "aiReview.model"

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        apiURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? "https://api.openai.com/v1"
        model = UserDefaults.standard.string(forKey: Self.modelKey) ?? "gpt-4.1-mini"
        let key = AIKeychain.read()
        apiKeyDraft = key
        hasSavedKey = !key.isEmpty
    }

    func saveKey() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if AIKeychain.save(key) {
            apiKeyDraft = key
            hasSavedKey = !key.isEmpty
            status = key.isEmpty ? L10n.text("API Key 已删除") : L10n.text("API Key 已保存到 macOS Keychain")
        } else {
            status = L10n.text("无法保存 API Key")
        }
    }

    func generate(for record: PostGameRecord, recent: [PostGameRecord]) async {
        guard enabled else { status = L10n.text("请先启用 AI 复盘"); return }
        let key = AIKeychain.read()
        guard !key.isEmpty else { status = L10n.text("请先保存 API Key"); return }
        guard let endpoint = completionEndpoint() else { status = L10n.text("AI 接口地址无效"); return }
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedModel.isEmpty else { status = L10n.text("请填写模型名称"); return }

        isGenerating = true
        status = L10n.text("正在生成 AI 复盘…")
        defer { isGenerating = false }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body = ChatCompletionRequest(
            model: selectedModel,
            messages: [
                .init(role: "system", content: "You are a concise League of Legends improvement coach. Analyze only the supplied player's aggregate match metrics. Do not invent events, timelines, opponents, rank, role, items, or causes that are absent. Give 2-4 specific, measurable next-game actions. Reply in \(LanguageSettings.shared.selection.title), with plain text and no markdown heading."),
                .init(role: "user", content: prompt(for: record, recent: recent))
            ],
            temperature: 0.3,
            max_tokens: 350
        )
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200..<300).contains(http.statusCode) else {
                let detail = try? JSONDecoder().decode(AIServiceError.self, from: data).error?.message
                status = L10n.text("AI 请求失败（HTTP %d）", http.statusCode) + (detail.map { ": \($0.prefix(180))" } ?? "")
                return
            }
            let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let text = result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                status = L10n.text("AI 返回了空内容"); return
            }
            advice = text
            status = L10n.text("AI 复盘已生成")
        } catch {
            status = L10n.text("AI 请求失败：%@", error.localizedDescription)
        }
    }

    private func completionEndpoint() -> URL? {
        let raw = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: raw),
              components.scheme == "https" || components.scheme == "http",
              let host = components.host, !host.isEmpty else { return nil }
        if components.scheme == "http", host != "localhost", host != "127.0.0.1", host != "::1" { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func prompt(for record: PostGameRecord, recent: [PostGameRecord]) -> String {
        let latest = String(format: "champion=%@, duration=%.1f min, K/D/A=%d/%d/%d, CS=%d, CS/min=%.2f, vision score=%.1f, vision/min=%.2f, KDA=%.2f",
                            record.champion, record.duration / 60, record.kills, record.deaths, record.assists,
                            record.creepScore, record.csPerMinute, record.wardScore, record.visionPerMinute, record.kda)
        let samples = Array(recent.prefix(10))
        guard !samples.isEmpty else { return "Latest match: \(latest)" }
        let cs = samples.reduce(0) { $0 + $1.csPerMinute } / Double(samples.count)
        let kda = samples.reduce(0) { $0 + $1.kda } / Double(samples.count)
        let deaths = Double(samples.reduce(0) { $0 + $1.deaths }) / Double(samples.count)
        return String(format: "Latest match: %@\nRecent sample: %d games, average CS/min=%.2f, average KDA=%.2f, average deaths=%.1f. State the data limitations clearly when relevant.", latest, samples.count, cs, kda, deaths)
    }
}
