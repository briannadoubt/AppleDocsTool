import Foundation

/// Parses build and test output into structured data
struct OutputParser {

    // MARK: - Build Output Parsing

    /// Parse Swift/Xcode build output for errors and warnings
    static func parseBuildOutput(_ output: String) -> (errors: [BuildDiagnostic], warnings: [BuildDiagnostic]) {
        var errors: [BuildDiagnostic] = []
        var warnings: [BuildDiagnostic] = []

        let lines = output.components(separatedBy: .newlines)

        // Pattern: /path/to/File.swift:42:10: error: message
        // Pattern: /path/to/File.swift:42:10: warning: message
        let diagnosticPattern = #"^(.+):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$"#
        let diagnosticRegex = try? NSRegularExpression(pattern: diagnosticPattern, options: [])

        for line in lines {
            if let match = diagnosticRegex?.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..., in: line)
            ) {
                guard match.numberOfRanges >= 6 else { continue }

                let file = extractGroup(match, 1, from: line)
                let lineNum = Int(extractGroup(match, 2, from: line))
                let column = Int(extractGroup(match, 3, from: line))
                let severityStr = extractGroup(match, 4, from: line)
                let message = extractGroup(match, 5, from: line)

                let severity: DiagnosticSeverity
                switch severityStr {
                case "error": severity = .error
                case "warning": severity = .warning
                default: severity = .note
                }

                let diagnostic = BuildDiagnostic(
                    message: message,
                    file: file,
                    line: lineNum,
                    column: column,
                    severity: severity
                )

                if severity == .error {
                    errors.append(diagnostic)
                } else if severity == .warning {
                    warnings.append(diagnostic)
                }
            }
        }

        return (errors, warnings)
    }

    /// Check if build output indicates success
    static func isBuildSuccessful(_ output: String) -> Bool {
        output.contains("Build complete!") ||
        output.contains("** BUILD SUCCEEDED **") ||
        (!output.contains("error:") && !output.contains("** BUILD FAILED **"))
    }

    // MARK: - Test Output Parsing

    /// Parse Swift test output into structured test results
    static func parseTestOutput(_ output: String) -> TestResult {
        var testCases: [TestCase] = []
        var currentFailureMessage: String?
        var currentFailureLocation: String?

        let lines = output.components(separatedBy: .newlines)

        // Patterns for test output
        // Test Case '-[ModuleTests.TestClass testMethod]' passed (0.001 seconds).
        // Test Case '-[ModuleTests.TestClass testMethod]' failed (0.001 seconds).
        let testCasePattern = #"Test Case '-\[(\S+)\.(\S+)\s+(\S+)\]' (passed|failed|skipped) \(([\d.]+) seconds\)"#
        let testCaseRegex = try? NSRegularExpression(pattern: testCasePattern, options: [])

        // Swift 5.x format: Test Case 'TestClass.testMethod' passed (0.001 seconds).
        let swiftTestPattern = #"Test Case '(\S+)\.(\S+)' (passed|failed|skipped) \(([\d.]+) seconds\)"#
        let swiftTestRegex = try? NSRegularExpression(pattern: swiftTestPattern, options: [])

        // Failure pattern: /path/File.swift:42: error: -[Module.Class testMethod] : XCTAssertEqual failed
        let failurePattern = #"(.+):(\d+): error: .+ : (.+)$"#
        let failureRegex = try? NSRegularExpression(pattern: failurePattern, options: [])

        for line in lines {
            // Check for failure details (comes before the test case result)
            if let failureMatch = failureRegex?.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..., in: line)
            ), failureMatch.numberOfRanges >= 4 {
                let file = extractGroup(failureMatch, 1, from: line)
                let lineNum = extractGroup(failureMatch, 2, from: line)
                currentFailureMessage = extractGroup(failureMatch, 3, from: line)
                currentFailureLocation = "\(file):\(lineNum)"
            }

            // Try Objective-C style format first
            if let match = testCaseRegex?.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..., in: line)
            ), match.numberOfRanges >= 6 {
                let moduleName = extractGroup(match, 1, from: line)
                let className = extractGroup(match, 2, from: line)
                let testName = extractGroup(match, 3, from: line)
                let statusStr = extractGroup(match, 4, from: line)
                let duration = Double(extractGroup(match, 5, from: line)) ?? 0

                let status: TestStatus
                switch statusStr {
                case "passed": status = .passed
                case "failed": status = .failed
                default: status = .skipped
                }

                let testCase = TestCase(
                    name: testName,
                    className: "\(moduleName).\(className)",
                    duration: duration,
                    status: status,
                    failureMessage: status == .failed ? currentFailureMessage : nil,
                    failureLocation: status == .failed ? currentFailureLocation : nil
                )
                testCases.append(testCase)

                // Reset failure info after using it
                if status == .failed {
                    currentFailureMessage = nil
                    currentFailureLocation = nil
                }
            }
            // Try Swift style format
            else if let match = swiftTestRegex?.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..., in: line)
            ), match.numberOfRanges >= 5 {
                let className = extractGroup(match, 1, from: line)
                let testName = extractGroup(match, 2, from: line)
                let statusStr = extractGroup(match, 3, from: line)
                let duration = Double(extractGroup(match, 4, from: line)) ?? 0

                let status: TestStatus
                switch statusStr {
                case "passed": status = .passed
                case "failed": status = .failed
                default: status = .skipped
                }

                let testCase = TestCase(
                    name: testName,
                    className: className,
                    duration: duration,
                    status: status,
                    failureMessage: status == .failed ? currentFailureMessage : nil,
                    failureLocation: status == .failed ? currentFailureLocation : nil
                )
                testCases.append(testCase)

                if status == .failed {
                    currentFailureMessage = nil
                    currentFailureLocation = nil
                }
            }
        }

        let passed = testCases.filter { $0.status == .passed }.count
        let failed = testCases.filter { $0.status == .failed }.count
        let skipped = testCases.filter { $0.status == .skipped }.count
        let totalDuration = testCases.reduce(0) { $0 + $1.duration }

        return TestResult(
            success: failed == 0,
            duration: totalDuration,
            totalTests: testCases.count,
            passed: passed,
            failed: failed,
            skipped: skipped,
            testCases: testCases,
            codeCoverage: nil
        )
    }

    // MARK: - Xcodebuild Output Parsing

    /// Parse xcodebuild -list JSON output for schemes
    static func parseSchemesList(_ output: String) -> [Scheme] {
        var schemes: [Scheme] = []

        // Try JSON format first (xcodebuild -list -json)
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            // Handle workspace format
            if let workspace = json["workspace"] as? [String: Any],
               let schemeNames = workspace["schemes"] as? [String] {
                schemes = schemeNames.map { Scheme(name: $0, isShared: nil) }
            }
            // Handle project format
            else if let project = json["project"] as? [String: Any],
                    let schemeNames = project["schemes"] as? [String] {
                schemes = schemeNames.map { Scheme(name: $0, isShared: nil) }
            }
        }

        // Fallback to text parsing
        if schemes.isEmpty {
            let lines = output.components(separatedBy: .newlines)
            var inSchemesSection = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed == "Schemes:" {
                    inSchemesSection = true
                    continue
                }

                if inSchemesSection {
                    if trimmed.isEmpty || trimmed.hasSuffix(":") {
                        break
                    }
                    schemes.append(Scheme(name: trimmed, isShared: nil))
                }
            }
        }

        return schemes
    }

    /// Parse xcodebuild -showdestinations output
    static func parseDestinations(_ output: String) -> [Destination] {
        var destinations: [Destination] = []

        let lines = output.components(separatedBy: .newlines)

        // Pattern: { platform:iOS Simulator, id:XXXXX, OS:17.0, name:iPhone 15 }
        let destPattern = #"\{\s*platform:([^,]+),\s*(?:id:([^,]+),\s*)?(?:OS:([^,]+),\s*)?name:([^}]+)\}"#
        let destRegex = try? NSRegularExpression(pattern: destPattern, options: [])

        for line in lines {
            if let match = destRegex?.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..., in: line)
            ) {
                let platform = extractGroup(match, 1, from: line).trimmingCharacters(in: .whitespaces)
                let id = match.range(at: 2).location != NSNotFound
                    ? extractGroup(match, 2, from: line).trimmingCharacters(in: .whitespaces)
                    : nil
                let os = match.range(at: 3).location != NSNotFound
                    ? extractGroup(match, 3, from: line).trimmingCharacters(in: .whitespaces)
                    : nil
                let name = extractGroup(match, 4, from: line).trimmingCharacters(in: .whitespaces)

                destinations.append(Destination(
                    platform: platform,
                    name: name,
                    id: id,
                    os: os,
                    arch: nil
                ))
            }
        }

        return destinations
    }

    // MARK: - Instruments Output Parsing

    /// Parse xctrace list templates output
    static func parseInstrumentsTemplates(_ output: String) -> [InstrumentTemplate] {
        var templates: [InstrumentTemplate] = []
        var currentCategory: String?

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Category headers like "== Standard =="
            if trimmed.hasPrefix("==") && trimmed.hasSuffix("==") {
                currentCategory = trimmed
                    .replacingOccurrences(of: "==", with: "")
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            // Template names are indented or just plain names
            if !trimmed.isEmpty && !trimmed.hasPrefix("==") {
                templates.append(InstrumentTemplate(
                    name: trimmed,
                    category: currentCategory
                ))
            }
        }

        return templates
    }

    // MARK: - Helper Methods

    private static func extractGroup(_ match: NSTextCheckingResult, _ group: Int, from string: String) -> String {
        guard group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: string) else {
            return ""
        }
        return String(string[range])
    }
}
