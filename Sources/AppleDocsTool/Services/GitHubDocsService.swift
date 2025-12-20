import Foundation

/// Service for fetching documentation from GitHub repositories
actor GitHubDocsService {
    private var cache: [String: GitHubDocs] = [:]
    private let maxCacheSize = 50

    struct GitHubDocs: Sendable {
        let repositoryName: String
        let repositoryURL: String
        let readme: String?
        let description: String?
        let topics: [String]
        let license: String?
        let stars: Int?
        let documentationFiles: [DocFile]

        struct DocFile: Sendable {
            let name: String
            let content: String
        }
    }

    /// Fetch documentation for a GitHub repository
    func fetchDocs(from urlString: String) async throws -> GitHubDocs {
        let repoInfo = try parseGitHubURL(urlString)

        let cacheKey = "\(repoInfo.owner)/\(repoInfo.repo)"
        if let cached = cache[cacheKey] {
            return cached
        }

        // Fetch repo metadata
        let repoData = try await fetchRepoMetadata(owner: repoInfo.owner, repo: repoInfo.repo)

        // Fetch README
        let readme = try? await fetchReadme(owner: repoInfo.owner, repo: repoInfo.repo)

        // Look for documentation files
        let docFiles = try await fetchDocumentationFiles(owner: repoInfo.owner, repo: repoInfo.repo)

        let docs = GitHubDocs(
            repositoryName: repoData.name,
            repositoryURL: repoData.htmlURL,
            readme: readme,
            description: repoData.description,
            topics: repoData.topics,
            license: repoData.license,
            stars: repoData.stars,
            documentationFiles: docFiles
        )

        addToCache(key: cacheKey, value: docs)
        return docs
    }

    /// Parse a GitHub URL to extract owner and repo
    private func parseGitHubURL(_ urlString: String) throws -> (owner: String, repo: String) {
        // Handle various GitHub URL formats:
        // https://github.com/owner/repo.git
        // https://github.com/owner/repo
        // git@github.com:owner/repo.git

        let url = urlString
            .replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
            .replacingOccurrences(of: ".git", with: "")

        guard let parsed = URL(string: url),
              let host = parsed.host,
              host.contains("github.com") else {
            throw GitHubDocsError.invalidURL(urlString)
        }

        let components = parsed.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else {
            throw GitHubDocsError.invalidURL(urlString)
        }

        return (owner: components[0], repo: components[1])
    }

    private struct RepoMetadata {
        let name: String
        let htmlURL: String
        let description: String?
        let topics: [String]
        let license: String?
        let stars: Int?
    }

    private func fetchRepoMetadata(owner: String, repo: String) async throws -> RepoMetadata {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)"
        guard let url = URL(string: urlString) else {
            throw GitHubDocsError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubDocsError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw GitHubDocsError.repositoryNotFound("\(owner)/\(repo)")
            }
            throw GitHubDocsError.networkError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubDocsError.parseError("Could not parse repository metadata")
        }

        let name = json["name"] as? String ?? repo
        let htmlURL = json["html_url"] as? String ?? "https://github.com/\(owner)/\(repo)"
        let description = json["description"] as? String
        let topics = json["topics"] as? [String] ?? []
        let stars = json["stargazers_count"] as? Int

        var license: String?
        if let licenseObj = json["license"] as? [String: Any] {
            license = licenseObj["name"] as? String
        }

        return RepoMetadata(
            name: name,
            htmlURL: htmlURL,
            description: description,
            topics: topics,
            license: license,
            stars: stars
        )
    }

    private func fetchReadme(owner: String, repo: String) async throws -> String {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/readme"
        guard let url = URL(string: urlString) else {
            throw GitHubDocsError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GitHubDocsError.readmeNotFound
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw GitHubDocsError.parseError("Could not decode README")
        }

        // Truncate very long READMEs
        if content.count > 15000 {
            let truncated = String(content.prefix(15000))
            return truncated + "\n\n... (README truncated, see full version on GitHub)"
        }

        return content
    }

    private func fetchDocumentationFiles(owner: String, repo: String) async throws -> [GitHubDocs.DocFile] {
        // Check common documentation locations
        let docPaths = [
            "Documentation",
            "Docs",
            "docs",
            "DOCUMENTATION.md",
            "USAGE.md",
            "GUIDE.md"
        ]

        var docFiles: [GitHubDocs.DocFile] = []

        for path in docPaths {
            if let content = try? await fetchFileContent(owner: owner, repo: repo, path: path) {
                docFiles.append(GitHubDocs.DocFile(name: path, content: content))
            }
        }

        return docFiles
    }

    private func fetchFileContent(owner: String, repo: String, path: String) async throws -> String {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)"
        guard let url = URL(string: urlString) else {
            throw GitHubDocsError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GitHubDocsError.fileNotFound(path)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw GitHubDocsError.parseError("Could not decode file content")
        }

        // Truncate very long files
        if content.count > 10000 {
            return String(content.prefix(10000)) + "\n\n... (truncated)"
        }

        return content
    }

    private func addToCache(key: String, value: GitHubDocs) {
        if cache.count >= maxCacheSize {
            let keysToRemove = Array(cache.keys.prefix(maxCacheSize / 2))
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }
        cache[key] = value
    }

    func clearCache() {
        cache.removeAll()
    }
}

enum GitHubDocsError: Error, LocalizedError {
    case invalidURL(String)
    case repositoryNotFound(String)
    case readmeNotFound
    case fileNotFound(String)
    case networkError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid GitHub URL: \(url)"
        case .repositoryNotFound(let repo):
            return "Repository not found: \(repo)"
        case .readmeNotFound:
            return "README not found in repository"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}
