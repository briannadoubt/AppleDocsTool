import Testing
@testable import AppleDocsToolCore

// MARK: - Test Fixtures

private func makeSymbol(
    name: String,
    fullyQualifiedName: String? = nil,
    documentation: String? = nil
) -> Symbol {
    Symbol(
        name: name,
        kind: .struct,
        moduleName: "TestModule",
        fullyQualifiedName: fullyQualifiedName ?? "TestModule.\(name)",
        declaration: "struct \(name)",
        documentation: documentation,
        filePath: nil,
        line: nil,
        accessLevel: .public,
        parameters: nil,
        returnType: nil
    )
}

private func makeDoc(title: String, identifier: String? = nil) -> AppleDocumentation {
    AppleDocumentation(
        identifier: identifier ?? "doc://\(title)",
        title: title,
        abstract: nil,
        declaration: nil,
        discussion: nil,
        parameters: nil,
        returnValue: nil,
        availability: nil,
        relatedSymbols: nil,
        url: nil,
        framework: "TestFramework"
    )
}

// MARK: - Match Type Tests

@Test func searchExactMatch() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "View"),
        makeSymbol(name: "ViewModel"),
        makeSymbol(name: "ViewBuilder")
    ]

    let results = await service.search(query: "View", symbols: symbols, source: "test")

    #expect(results.count >= 1)
    #expect(results[0].name == "View")
    #expect(results[0].matchType == "exact")
    #expect(results[0].score > 0.99)  // Exact match boosted by 1.1
}

@Test func searchPrefixMatch() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "ViewModel"),
        makeSymbol(name: "Something")
    ]

    let results = await service.search(query: "View", symbols: symbols, source: "test")

    #expect(results.count == 1)
    #expect(results[0].name == "ViewModel")
    #expect(results[0].matchType == "prefix")
}

@Test func searchCamelCaseMatch() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "ViewModel"),
        makeSymbol(name: "ViewController"),
        makeSymbol(name: "URLSessionTask")
    ]

    let results = await service.search(query: "VM", symbols: symbols, source: "test")

    // "VM" should match "ViewModel" via camelCase
    #expect(results.count >= 1)
    let vmMatch = results.first { $0.name == "ViewModel" }
    #expect(vmMatch != nil)
    #expect(vmMatch?.matchType == "camelCase")
}

@Test func searchCamelCaseMatchVC() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "ViewController"),
        makeSymbol(name: "VeryClever")
    ]

    let results = await service.search(query: "VC", symbols: symbols, source: "test")

    #expect(results.count == 2)
    // Both should match "VC" camelCase
}

@Test func searchContainsMatch() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "MyCustomView"),
        makeSymbol(name: "Something")
    ]

    let results = await service.search(query: "custom", symbols: symbols, source: "test")

    #expect(results.count == 1)
    #expect(results[0].name == "MyCustomView")
    #expect(results[0].matchType == "contains")
}

@Test func searchFuzzyMatch() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "Button"),
        makeSymbol(name: "Label")
    ]

    // "Buton" (typo) should fuzzy match "Button"
    let results = await service.search(query: "buton", symbols: symbols, source: "test")

    #expect(results.count >= 1)
    let buttonMatch = results.first { $0.name == "Button" }
    #expect(buttonMatch != nil)
    #expect(buttonMatch?.matchType == "fuzzy")
}

@Test func searchNoMatch() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "Button"),
        makeSymbol(name: "Label")
    ]

    let results = await service.search(query: "xyz123", symbols: symbols, source: "test")

    #expect(results.isEmpty)
}

@Test func searchDocumentationMatch() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "MyStruct", documentation: "A widget for displaying content")
    ]

    let results = await service.search(query: "widget", symbols: symbols, source: "test")

    #expect(results.count == 1)
    #expect(results[0].matchType == "documentation")
}

// MARK: - Ranking Tests

@Test func rankingExactMatchFirst() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "ViewBuilder"),  // prefix match
        makeSymbol(name: "View"),          // exact match
        makeSymbol(name: "MyView")          // contains match
    ]

    let results = await service.search(query: "view", symbols: symbols, source: "test")

    #expect(results.count == 3)
    #expect(results[0].name == "View")  // exact match first
}

@Test func rankingPrefixBeforeContains() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "MyButton"),  // contains
        makeSymbol(name: "ButtonStyle") // prefix
    ]

    let results = await service.search(query: "button", symbols: symbols, source: "test")

    #expect(results.count == 2)
    #expect(results[0].name == "ButtonStyle")  // prefix first
}

@Test func rankingShorterMatchesPreferred() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "TextFieldStyle"),  // longer
        makeSymbol(name: "TextField"),        // shorter
        makeSymbol(name: "TextFieldConfiguration")  // longest
    ]

    let results = await service.search(query: "textfield", symbols: symbols, source: "test")

    // All are exact matches case-insensitively, shorter should be first
    #expect(results.count == 3)
    #expect(results[0].name == "TextField")  // shortest
}

// MARK: - Merge Results Tests

@Test func mergeResultsFromMultipleSources() async {
    let service = SearchService()

    let set1 = [
        SearchService.ScoredResult(
            name: "ViewA", fullyQualifiedName: "M.ViewA", kind: "struct",
            source: "source1", declaration: nil, documentation: nil, score: 0.9, matchType: "prefix"
        )
    ]
    let set2 = [
        SearchService.ScoredResult(
            name: "ViewB", fullyQualifiedName: "M.ViewB", kind: "struct",
            source: "source2", declaration: nil, documentation: nil, score: 1.0, matchType: "exact"
        )
    ]

    let merged = await service.mergeResults([set1, set2])

    #expect(merged.count == 2)
    #expect(merged[0].name == "ViewB")  // higher score first
    #expect(merged[1].name == "ViewA")
}

@Test func mergeResultsMaxResults() async {
    let service = SearchService()

    var results: [SearchService.ScoredResult] = []
    for i in 0..<10 {
        results.append(SearchService.ScoredResult(
            name: "Item\(i)", fullyQualifiedName: "M.Item\(i)", kind: "struct",
            source: "test", declaration: nil, documentation: nil, score: Double(10 - i) / 10.0, matchType: "prefix"
        ))
    }

    let merged = await service.mergeResults([results], maxResults: 5)

    #expect(merged.count == 5)
    #expect(merged[0].name == "Item0")  // highest score
}

// MARK: - Apple Docs Search Tests

@Test func searchAppleDocsExactMatch() async {
    let service = SearchService()
    let docs = [
        makeDoc(title: "View"),
        makeDoc(title: "ViewBuilder"),
        makeDoc(title: "Text")
    ]

    let results = await service.searchAppleDocs(query: "View", docs: docs, framework: "SwiftUI")

    #expect(results.count >= 1)
    #expect(results[0].name == "View")
    #expect(results[0].matchType == "exact")
    #expect(results[0].source == "apple:SwiftUI")
}

@Test func searchAppleDocsPrefixMatch() async {
    let service = SearchService()
    let docs = [
        makeDoc(title: "URLSession"),
        makeDoc(title: "URLRequest"),
        makeDoc(title: "Data")
    ]

    let results = await service.searchAppleDocs(query: "URL", docs: docs, framework: "Foundation")

    #expect(results.count == 2)
    // Both URL-prefixed should match
}

// MARK: - Edge Cases

@Test func searchEmptyQuery() async {
    let service = SearchService()
    let symbols = [makeSymbol(name: "Test")]

    let results = await service.search(query: "", symbols: symbols, source: "test")

    // Empty query matches everything as exact empty match
    #expect(results.count == 1)
}

@Test func searchEmptySymbols() async {
    let service = SearchService()

    let results = await service.search(query: "test", symbols: [], source: "test")

    #expect(results.isEmpty)
}

@Test func searchMaxResults() async {
    let service = SearchService()
    var symbols: [Symbol] = []
    for i in 0..<100 {
        symbols.append(makeSymbol(name: "Test\(i)"))
    }

    let results = await service.search(query: "test", symbols: symbols, source: "test", maxResults: 10)

    #expect(results.count == 10)
}

@Test func searchCaseInsensitive() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "MyClass"),
        makeSymbol(name: "MYCLASS"),
        makeSymbol(name: "myclass")
    ]

    let results = await service.search(query: "MYCLASS", symbols: symbols, source: "test")

    // All should match (case insensitive)
    #expect(results.count == 3)
}

@Test func searchSubsequenceMatch() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "NavigationController")
    ]

    // "nvc" as subsequence of "NavigationController"
    let results = await service.search(query: "nvc", symbols: symbols, source: "test")

    #expect(results.count == 1)
    #expect(results[0].matchType == "subsequence")
}

@Test func searchWordBoundaryMatch() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "my_custom_view")  // underscore separated
    ]

    let results = await service.search(query: "custom", symbols: symbols, source: "test")

    #expect(results.count == 1)
    // Should match via word boundary or contains
}

@Test func searchFullyQualifiedNameMatch() async {
    let service = SearchService()
    let symbols = [
        makeSymbol(name: "View", fullyQualifiedName: "SwiftUI.View")
    ]

    let results = await service.search(query: "swiftui", symbols: symbols, source: "test")

    #expect(results.count == 1)
    // Should match via FQN
}
