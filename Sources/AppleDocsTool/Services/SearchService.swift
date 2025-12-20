import Foundation

/// Service for searching symbols with fuzzy matching and relevance ranking
actor SearchService {

    /// Search result with relevance score
    struct ScoredResult: Codable, Sendable {
        let name: String
        let fullyQualifiedName: String
        let kind: String
        let source: String
        let declaration: String?
        let documentation: String?
        let score: Double
        let matchType: String // "exact", "prefix", "contains", "fuzzy"
    }

    /// Search symbols with fuzzy matching and ranking
    func search(
        query: String,
        symbols: [Symbol],
        source: String,
        maxResults: Int = 50
    ) -> [ScoredResult] {
        let queryLower = query.lowercased()
        var results: [ScoredResult] = []

        for symbol in symbols {
            if let score = scoreMatch(query: queryLower, symbol: symbol) {
                results.append(ScoredResult(
                    name: symbol.name,
                    fullyQualifiedName: symbol.fullyQualifiedName,
                    kind: symbol.kind.rawValue,
                    source: source,
                    declaration: symbol.declaration,
                    documentation: symbol.documentation,
                    score: score.score,
                    matchType: score.matchType
                ))
            }
        }

        // Sort by score (descending) then by name length (prefer shorter names)
        results.sort {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.name.count < $1.name.count
        }

        return Array(results.prefix(maxResults))
    }

    /// Search Apple documentation with scoring
    func searchAppleDocs(
        query: String,
        docs: [AppleDocumentation],
        framework: String,
        maxResults: Int = 20
    ) -> [ScoredResult] {
        let queryLower = query.lowercased()
        var results: [ScoredResult] = []

        for doc in docs {
            let nameLower = doc.title.lowercased()

            if let score = scoreStringMatch(query: queryLower, target: nameLower, targetOriginal: doc.title) {
                results.append(ScoredResult(
                    name: doc.title,
                    fullyQualifiedName: doc.identifier,
                    kind: "apple-symbol",
                    source: "apple:\(framework)",
                    declaration: doc.declaration,
                    documentation: doc.abstract,
                    score: score.score,
                    matchType: score.matchType
                ))
            }
        }

        results.sort {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.name.count < $1.name.count
        }

        return Array(results.prefix(maxResults))
    }

    /// Merge and re-rank results from multiple sources
    func mergeResults(_ resultSets: [[ScoredResult]], maxResults: Int = 100) -> [ScoredResult] {
        var allResults = resultSets.flatMap { $0 }

        // Sort by score descending
        allResults.sort {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.name.count < $1.name.count
        }

        return Array(allResults.prefix(maxResults))
    }

    // MARK: - Private Scoring Methods

    private struct MatchScore {
        let score: Double
        let matchType: String
    }

    private func scoreMatch(query: String, symbol: Symbol) -> MatchScore? {
        let nameLower = symbol.name.lowercased()
        let fqnLower = symbol.fullyQualifiedName.lowercased()

        // Check name first (higher priority)
        if let nameScore = scoreStringMatch(query: query, target: nameLower, targetOriginal: symbol.name) {
            // Boost score slightly for name matches vs FQN matches
            return MatchScore(score: nameScore.score * 1.1, matchType: nameScore.matchType)
        }

        // Check fully qualified name
        if let fqnScore = scoreStringMatch(query: query, target: fqnLower, targetOriginal: symbol.fullyQualifiedName) {
            return fqnScore
        }

        // Check documentation for partial matches (lower score)
        if let doc = symbol.documentation?.lowercased(), doc.contains(query) {
            return MatchScore(score: 0.3, matchType: "documentation")
        }

        return nil
    }

    private func scoreStringMatch(query: String, target: String, targetOriginal: String) -> MatchScore? {
        // Exact match
        if target == query {
            return MatchScore(score: 1.0, matchType: "exact")
        }

        // Prefix match (starts with query)
        if target.hasPrefix(query) {
            // Score based on how much of the target is covered
            let coverage = Double(query.count) / Double(target.count)
            return MatchScore(score: 0.9 + (coverage * 0.09), matchType: "prefix")
        }

        // Camel case prefix match (e.g., "VM" matches "ViewModel")
        if matchesCamelCasePrefix(query: query, target: targetOriginal) {
            return MatchScore(score: 0.85, matchType: "camelCase")
        }

        // Contains match
        if target.contains(query) {
            // Score based on how much of the target is covered
            let coverage = Double(query.count) / Double(target.count)
            return MatchScore(score: 0.6 + (coverage * 0.2), matchType: "contains")
        }

        // Word boundary match (query matches word boundaries)
        if matchesWordBoundaries(query: query, target: target) {
            return MatchScore(score: 0.7, matchType: "wordBoundary")
        }

        // Fuzzy match with Levenshtein distance
        let distance = levenshteinDistance(query, target)
        let maxLen = max(query.count, target.count)
        let similarity = 1.0 - (Double(distance) / Double(maxLen))

        // Only consider fuzzy matches with > 60% similarity
        if similarity > 0.6 {
            return MatchScore(score: similarity * 0.5, matchType: "fuzzy")
        }

        // Subsequence match (all query characters appear in order)
        if isSubsequence(query: query, of: target) {
            let coverage = Double(query.count) / Double(target.count)
            return MatchScore(score: 0.4 + (coverage * 0.1), matchType: "subsequence")
        }

        return nil
    }

    /// Check if query matches camel case initials (e.g., "VM" matches "ViewModel")
    private func matchesCamelCasePrefix(query: String, target: String) -> Bool {
        let queryUpper = query.uppercased()
        var initials = ""

        for (index, char) in target.enumerated() {
            if char.isUppercase || index == 0 {
                initials.append(char.uppercased())
            }
        }

        return initials.hasPrefix(queryUpper)
    }

    /// Check if query matches word boundaries in target
    private func matchesWordBoundaries(query: String, target: String) -> Bool {
        // Split by common separators and check if any word starts with query
        let words = target.split { !$0.isLetter && !$0.isNumber }
        for word in words {
            if word.lowercased().hasPrefix(query) {
                return true
            }
        }
        return false
    }

    /// Check if query is a subsequence of target
    private func isSubsequence(query: String, of target: String) -> Bool {
        var queryIndex = query.startIndex

        for char in target {
            if queryIndex < query.endIndex && char == query[queryIndex] {
                queryIndex = query.index(after: queryIndex)
            }
        }

        return queryIndex == query.endIndex
    }

    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        // Use two rows instead of full matrix for memory efficiency
        var prevRow = Array(0...n)
        var currRow = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            currRow[0] = i

            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                currRow[j] = min(
                    currRow[j - 1] + 1,      // insertion
                    prevRow[j] + 1,          // deletion
                    prevRow[j - 1] + cost    // substitution
                )
            }

            swap(&prevRow, &currRow)
        }

        return prevRow[n]
    }
}
