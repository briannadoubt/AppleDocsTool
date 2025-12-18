import Foundation

/// Service for fetching Apple documentation from the web
actor AppleDocsService {
    private var cache: [String: AppleDocsResponse] = [:]
    private let baseURL = "https://developer.apple.com/tutorials/data/documentation"

    /// Fetch documentation for a framework
    func fetchFrameworkDocs(framework: String) async throws -> AppleDocsResponse {
        let cacheKey = framework.lowercased()

        if let cached = cache[cacheKey] {
            return cached
        }

        let urlString = "\(baseURL)/\(framework.lowercased()).json"
        guard let url = URL(string: urlString) else {
            throw AppleDocsError.invalidURL(urlString)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppleDocsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AppleDocsError.httpError(httpResponse.statusCode)
        }

        let docs = try JSONDecoder().decode(AppleDocsResponse.self, from: data)
        cache[cacheKey] = docs
        return docs
    }

    /// Fetch documentation for a specific symbol within a framework
    func fetchSymbolDocs(framework: String, symbolPath: String) async throws -> AppleDocsResponse {
        let normalizedPath = symbolPath.lowercased().replacingOccurrences(of: ".", with: "/")
        let cacheKey = "\(framework.lowercased())/\(normalizedPath)"

        if let cached = cache[cacheKey] {
            return cached
        }

        let urlString = "\(baseURL)/\(framework.lowercased())/\(normalizedPath).json"
        guard let url = URL(string: urlString) else {
            throw AppleDocsError.invalidURL(urlString)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppleDocsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AppleDocsError.httpError(httpResponse.statusCode)
        }

        let docs = try JSONDecoder().decode(AppleDocsResponse.self, from: data)
        cache[cacheKey] = docs
        return docs
    }

    /// Search for a symbol across framework documentation
    func searchSymbol(query: String, in framework: String) async throws -> [AppleDocumentation] {
        let frameworkDocs = try await fetchFrameworkDocs(framework: framework)
        var results: [AppleDocumentation] = []

        // Search in references
        if let references = frameworkDocs.references {
            let queryLower = query.lowercased()

            for (_, ref) in references {
                guard let title = ref.title else { continue }

                if title.lowercased().contains(queryLower) {
                    let abstract = ref.abstract?.compactMap { content -> String? in
                        content.text ?? content.code
                    }.joined(separator: " ")

                    let declaration = ref.fragments?.map { $0.text }.joined()

                    results.append(AppleDocumentation(
                        identifier: ref.identifier,
                        title: title,
                        abstract: abstract,
                        declaration: declaration,
                        discussion: nil,
                        parameters: nil,
                        returnValue: nil,
                        availability: nil,
                        relatedSymbols: nil,
                        url: ref.url.map { "https://developer.apple.com\($0)" },
                        framework: framework
                    ))
                }
            }
        }

        return results
    }

    /// Convert AppleDocsResponse to AppleDocumentation model
    func convertToDocumentation(_ response: AppleDocsResponse, framework: String) -> AppleDocumentation {
        let abstract = response.abstract?.compactMap { content -> String? in
            content.text ?? content.code
        }.joined(separator: " ")

        var declaration: String?
        var discussion: String?
        var parameters: [AppleDocumentation.DocumentationParameter]?
        let returnValue: String? = nil

        if let sections = response.primaryContentSections {
            for section in sections {
                switch section.kind {
                case "declarations":
                    if let decl = section.declarations?.first?.tokens {
                        declaration = decl.map { $0.text }.joined()
                    }

                case "content":
                    discussion = extractTextContent(from: section.content)

                case "parameters":
                    parameters = section.parameters?.map { param in
                        AppleDocumentation.DocumentationParameter(
                            name: param.name,
                            discussion: extractTextContent(from: param.content)
                        )
                    }

                default:
                    break
                }
            }
        }

        let availability = response.metadata.platforms?.map { platform in
            AppleDocumentation.PlatformAvailability(
                platform: platform.name,
                introducedAt: platform.introducedAt,
                deprecatedAt: nil
            )
        }

        var relatedSymbols: [AppleDocumentation.RelatedSymbol]?
        if let topics = response.topicSections, let references = response.references {
            relatedSymbols = topics.flatMap { topic in
                topic.identifiers.compactMap { id -> AppleDocumentation.RelatedSymbol? in
                    guard let ref = references[id], let title = ref.title else { return nil }
                    return AppleDocumentation.RelatedSymbol(
                        title: title,
                        identifier: id,
                        kind: ref.kind
                    )
                }
            }
        }

        let url = response.identifier.url
            .replacingOccurrences(of: "doc://com.apple.", with: "https://developer.apple.com/documentation/")
            .replacingOccurrences(of: "doc://com.apple.documentation/documentation/", with: "https://developer.apple.com/documentation/")

        return AppleDocumentation(
            identifier: response.identifier.url,
            title: response.metadata.title,
            abstract: abstract,
            declaration: declaration,
            discussion: discussion,
            parameters: parameters,
            returnValue: returnValue,
            availability: availability,
            relatedSymbols: relatedSymbols,
            url: url,
            framework: framework
        )
    }

    private func extractTextContent(from content: [AppleDocsResponse.AppleDocsContent]?) -> String? {
        guard let content = content else { return nil }

        var text: [String] = []

        for item in content {
            if let inline = item.inlineContent {
                for element in inline {
                    if let t = element.text {
                        text.append(t)
                    } else if let code = element.code {
                        text.append("`\(code)`")
                    }
                }
            }

            if let nested = item.content {
                if let nestedText = extractTextContent(from: nested) {
                    text.append(nestedText)
                }
            }

            if let items = item.items {
                for listItem in items {
                    if let itemText = extractTextContent(from: listItem.content) {
                        text.append("• \(itemText)")
                    }
                }
            }
        }

        return text.isEmpty ? nil : text.joined(separator: " ")
    }

    /// Clear the cache
    func clearCache() {
        cache.removeAll()
    }
}

enum AppleDocsError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)
    case notFound(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Invalid response from Apple documentation server"
        case .httpError(let code):
            return "HTTP error \(code) from Apple documentation server"
        case .notFound(let symbol):
            return "Documentation not found for: \(symbol)"
        case .parseError(let message):
            return "Failed to parse documentation: \(message)"
        }
    }
}
