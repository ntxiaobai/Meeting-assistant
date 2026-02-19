import Foundation

final class MicrosoftTranslatorClient: TextTranslator {
    private enum ApiMode {
        case translatorV3
        case translatorPreview2025
    }

    enum MicrosoftTranslatorError: LocalizedError {
        case missingApiKey
        case invalidEndpoint
        case insecureEndpoint
        case unsupportedEndpointHost(String)
        case unsupportedEndpointPath(String)
        case badResponse(status: Int, body: String)
        case invalidPayload
        case networkFailure(String)

        var errorDescription: String? {
            switch self {
            case .missingApiKey:
                return "Microsoft Translator API key is missing."
            case .invalidEndpoint:
                return "Microsoft Translator endpoint is invalid."
            case .insecureEndpoint:
                return "Microsoft Translator endpoint must use HTTPS."
            case let .unsupportedEndpointHost(host):
                return "Unsupported endpoint host: \(host). Use a Translator endpoint (api.cognitive.microsofttranslator.com or <resource>.cognitiveservices.azure.com)."
            case let .unsupportedEndpointPath(path):
                return "Unsupported endpoint path: \(path). Use /translate or /translator/text/v3.0/translate."
            case let .badResponse(status, body):
                return "Microsoft Translator request failed: status=\(status), body=\(body)"
            case .invalidPayload:
                return "Microsoft Translator returned invalid payload."
            case let .networkFailure(reason):
                return "Microsoft Translator network error: \(reason)"
            }
        }
    }

    private let apiKey: String
    private let endpoint: String
    private let region: String
    private let session: URLSession

    init(apiKey: String, endpoint: String, region: String, session: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        self.region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func translate(text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw MicrosoftTranslatorError.missingApiKey
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let source = normalizeSourceLanguage(sourceLanguage)
        let target = normalizeTargetLanguage(targetLanguage)
        let requestContext = try buildRequestContext(source: source, target: target)
        let bodyPayload: Any
        switch requestContext.mode {
        case .translatorV3:
            bodyPayload = [["text": text]]
        case .translatorPreview2025:
            bodyPayload = [
                "inputs": [[
                    "text": text,
                    "language": source,
                    "targets": [["language": target]],
                ]],
            ]
        }
        let bodyData = try JSONSerialization.data(withJSONObject: bodyPayload)

        var request = URLRequest(url: requestContext.url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-ClientTraceId")
        if !region.isEmpty {
            request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapNetworkError(error)
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw MicrosoftTranslatorError.badResponse(status: statusCode, body: body)
        }

        let raw = try JSONSerialization.jsonObject(with: data)
        guard let result = extractTranslatedText(from: raw) else {
            throw MicrosoftTranslatorError.invalidPayload
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension MicrosoftTranslatorClient {
    private struct RequestContext {
        var url: URL
        var mode: ApiMode
    }

    private func buildRequestContext(source: String, target: String) throws -> RequestContext {
        guard var components = URLComponents(string: endpoint),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            throw MicrosoftTranslatorError.invalidEndpoint
        }

        guard components.scheme?.lowercased() == "https" else {
            throw MicrosoftTranslatorError.insecureEndpoint
        }

        let lowercasedHost = host.lowercased()
        if lowercasedHost.contains("services.ai.azure.com") {
            throw MicrosoftTranslatorError.unsupportedEndpointHost(host)
        }

        let normalizedPath = normalizePath(components.path)
        let mode = detectApiMode(path: normalizedPath, queryItems: components.queryItems)

        switch mode {
        case .translatorV3:
            if normalizedPath.isEmpty {
                components.path = "/translate"
            } else if normalizedPath == "/translate" {
                components.path = normalizedPath
            } else if normalizedPath.hasSuffix("/translator/text/v3.0/translate") {
                components.path = normalizedPath
            } else if normalizedPath.hasSuffix("/translator/text/v3.0") {
                components.path = "\(normalizedPath)/translate"
            } else {
                throw MicrosoftTranslatorError.unsupportedEndpointPath(normalizedPath)
            }

            var queryItems = components.queryItems ?? []
            if !components.path.hasSuffix("/translator/text/v3.0/translate") {
                upsertQueryItem(name: "api-version", value: "3.0", in: &queryItems)
            } else {
                removeQueryItem(name: "api-version", in: &queryItems)
            }
            upsertQueryItem(name: "from", value: source, in: &queryItems)
            upsertQueryItem(name: "to", value: target, in: &queryItems)
            components.queryItems = queryItems

        case .translatorPreview2025:
            if normalizedPath.isEmpty || normalizedPath == "/" {
                components.path = "/translate"
            } else if normalizedPath.hasSuffix("/translate") || normalizedPath.hasSuffix("/translator/text/translate") {
                components.path = normalizedPath
            } else {
                throw MicrosoftTranslatorError.unsupportedEndpointPath(normalizedPath)
            }

            var queryItems = components.queryItems ?? []
            let version = queryItems.first(where: { $0.name == "api-version" })?.value ?? "2025-10-01-preview"
            upsertQueryItem(name: "api-version", value: version, in: &queryItems)
            removeQueryItem(name: "from", in: &queryItems)
            removeQueryItem(name: "to", in: &queryItems)
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw MicrosoftTranslatorError.invalidEndpoint
        }
        return RequestContext(url: url, mode: mode)
    }

    func normalizePath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ""
        }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    private func detectApiMode(path: String, queryItems: [URLQueryItem]?) -> ApiMode {
        let apiVersion = queryItems?.first(where: { $0.name == "api-version" })?.value?.lowercased()
        if path.contains("/translator/text/translate") || (apiVersion?.contains("preview") == true) {
            return .translatorPreview2025
        }
        return .translatorV3
    }

    func upsertQueryItem(name: String, value: String, in queryItems: inout [URLQueryItem]) {
        if let index = queryItems.firstIndex(where: { $0.name == name }) {
            queryItems[index] = URLQueryItem(name: name, value: value)
        } else {
            queryItems.append(URLQueryItem(name: name, value: value))
        }
    }

    func removeQueryItem(name: String, in queryItems: inout [URLQueryItem]) {
        queryItems.removeAll { $0.name == name }
    }

    func extractTranslatedText(from raw: Any) -> String? {
        if let list = raw as? [[String: Any]],
           let first = list.first,
           let text = extractTranslationText(from: first)
        {
            return text
        }

        if let dict = raw as? [String: Any],
           let values = dict["value"] as? [[String: Any]],
           let first = values.first,
           let text = extractTranslationText(from: first)
        {
            return text
        }

        return nil
    }

    func extractTranslationText(from entry: [String: Any]) -> String? {
        guard let translations = entry["translations"] as? [[String: Any]],
              let result = translations.first?["text"] as? String
        else {
            return nil
        }
        return result
    }

    func mapNetworkError(_ error: Error) -> MicrosoftTranslatorError {
        if let urlError = error as? URLError {
            let hint: String
            switch urlError.code {
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                hint = "SSL handshake failed. Verify endpoint host and certificate chain."
            case .cannotFindHost, .cannotConnectToHost:
                hint = "Cannot reach endpoint host."
            default:
                hint = "URLError code=\(urlError.code.rawValue)."
            }
            return .networkFailure("\(urlError.localizedDescription) (\(hint))")
        }
        return .networkFailure(error.localizedDescription)
    }

    func normalizeSourceLanguage(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "cn", "zh", "zh-cn", "chinese", "中文":
            return "zh-Hans"
        case "en", "english":
            return "en"
        case "ja", "japanese", "日语":
            return "ja"
        case "ko", "korean", "韩语":
            return "ko"
        default:
            return normalized
        }
    }

    func normalizeTargetLanguage(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "cn", "zh", "zh-cn", "chinese", "中文":
            return "zh-Hans"
        case "en", "english":
            return "en"
        case "ja", "japanese", "日语":
            return "ja"
        case "ko", "korean", "韩语":
            return "ko"
        case "de", "german", "德语":
            return "de"
        case "fr", "french", "法语":
            return "fr"
        case "ru", "russian", "俄语":
            return "ru"
        default:
            return normalized
        }
    }
}
