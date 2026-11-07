import Foundation

enum AIError: Error {
    case noKey
    case network
    case status(Int, String)
    case format
    case refusal
}

/// 直接打 Anthropic Messages API。只有週對帳按「請 AI 讀」時才會送資料出去。
enum AIClient {
    static let defaultModel = "claude-sonnet-5-5"

    static let rules = """
你是日記 app「蒜數」裡的對帳助手。使用者用這個 app 改進自己：白天用說的記下零碎片段，睡前把一天切成上午、下午、晚上，各點一下「順／普通／卡」。
規則（一定要守）：
1. 先講數字和使用者的原話，再講你的看法。計數以 app 給的數字為準，你不要自己數。
2. 不問「為什麼」，只問看得到答案的事：當時在做什麼、前面發生什麼、跟誰。
3. 你提的模式都是猜測，不是結論。
4. 不解夢、不做人格或價值判斷、不替使用者下人生意義的結論、不替使用者命名情緒。
5. 不附和、不陪著抱怨。使用者一直重複同一個煩惱時，請他把它換成一個具體問題。
6. 對話最後收在一個下週可以做的小實驗：什麼時候、做什麼、怎樣算有效。實驗一次只改一件事。
7. 不寫週摘要。
用繁體中文（台灣用語），口語、簡短，每次回覆不超過 150 字。
"""

    /// effort 控制想多久：候選用 medium，聊天用 low。
    /// max_tokens 要留夠，因為 Sonnet 5.5 的 thinking 也算在裡面。
    static func complete(key: String, model: String, messages: [[String: String]],
                         maxTokens: Int = 4096, effort: String = "low") async -> Result<String, AIError> {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return .failure(.noKey) }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return .failure(.network) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        let trimmedModel = model.trimmingCharacters(in: .whitespaces)
        let body: [String: Any] = [
            "model": trimmedModel.isEmpty ? defaultModel : trimmedModel,
            "max_tokens": maxTokens,
            "system": rules,
            "messages": messages,
            "output_config": ["effort": effort],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return .failure(.format) }
        req.httpBody = data

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: req)
        } catch {
            return .failure(.network)
        }
        guard let http = result.1 as? HTTPURLResponse else { return .failure(.network) }
        let json = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any]
        if http.statusCode != 200 {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
            return .failure(.status(http.statusCode, msg))
        }
        if (json?["stop_reason"] as? String) == "refusal" { return .failure(.refusal) }
        let blocks = (json?["content"] as? [[String: Any]]) ?? []
        let text = blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        return .success(text)
    }

    /// 從 AI 的回覆裡挖出 {"candidates":[...]}，最多留三條
    static func parseCandidates(_ text: String) -> [AICandidate]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        let sub = String(text[start...end])
        guard let d = sub.data(using: .utf8),
              let env = try? JSONDecoder().decode(AICandidatesEnvelope.self, from: d) else { return nil }
        let good = (env.candidates ?? [])
            .compactMap { $0.value }
            .filter { !$0.name.isEmpty && !$0.keywords.isEmpty }
        return Array(good.prefix(3))
    }

    static func message(for e: AIError) -> String {
        switch e {
        case .noKey:
            return "還沒設定 AI 金鑰。到設定頁「AI 對帳」貼上你的 Anthropic API 金鑰。"
        case .network:
            return "連不到 AI。檢查網路再試一次。"
        case .refusal:
            return "AI 這次沒有回答。換個說法，或等一下再試。"
        case .format:
            return "AI 回的格式讀不懂，再試一次。"
        case .status(let code, let msg):
            if code == 401 { return "金鑰被拒絕了，檢查設定頁的金鑰有沒有貼完整。" }
            if code == 404 { return "找不到這個模型名稱，到設定頁改一下模型。" }
            if code == 429 { return "AI 那邊太忙，等一下再試。" }
            let short = String(msg.prefix(120))
            return "AI 回覆失敗（\(code)\(short.isEmpty ? "" : " " + short)），等一下再試。"
        }
    }
}
