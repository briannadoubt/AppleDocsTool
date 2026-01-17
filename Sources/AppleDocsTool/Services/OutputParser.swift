import Foundation

/// Parses build and test output into structured data
struct OutputParser {

    // MARK: - Build Output Parsing

    /// Parse Swift/Xcode build output for errors and warnings
    static func parseBuildOutput(_ output: String) -> (errors: [BuildDiagnostic], warnings: [BuildDiagnostic]) {
        var errors: [BuildDiagnostic] = []
        var warnings: [BuildDiagnostic] = []

        let lines = output.components(separatedBy: .newlines)

        // Pattern 1: /path/to/File.swift:42:10: error: message
        let diagnosticPattern = #"^(.+):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$"#
        let diagnosticRegex = try? NSRegularExpression(pattern: diagnosticPattern, options: [])

        // Pattern 2: error: message (no file location)
        // Matches: "error: Module 'X' not found", "xcodebuild: error: ...", etc.
        let simpleErrorPattern = #"^(?:xcodebuild:\s*)?(error|warning):\s*(.+)$"#
        let simpleErrorRegex = try? NSRegularExpression(pattern: simpleErrorPattern, options: [.caseInsensitive])

        // Pattern 3: Linker errors - "ld: library not found for -lXXX"
        let linkerErrorPattern = #"^ld:\s*(.+)$"#
        let linkerErrorRegex = try? NSRegularExpression(pattern: linkerErrorPattern, options: [])

        // Pattern 4: Clang errors - "clang: error: xxx"
        let clangErrorPattern = #"^clang:\s*(error|warning):\s*(.+)$"#
        let clangErrorRegex = try? NSRegularExpression(pattern: clangErrorPattern, options: [])

        // Track failed build commands section
        var inFailedCommandsSection = false
        var failedCommands: [String] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Check for "The following build commands failed:" section
            if trimmedLine.contains("The following build commands failed:") {
                inFailedCommandsSection = true
                continue
            }

            if inFailedCommandsSection {
                // End of failed commands section (usually ends with a count line)
                if trimmedLine.hasPrefix("(") && trimmedLine.contains("failure") {
                    inFailedCommandsSection = false
                    continue
                }
                // Capture failed command
                if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("**") {
                    failedCommands.append(trimmedLine)
                }
                continue
            }

            // Pattern 1: File with line/column location
            if let match = diagnosticRegex?.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..., in: line)
            ), match.numberOfRanges >= 6 {

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
                continue
            }

            // Pattern 2: Simple error/warning without file location
            if let match = simpleErrorRegex?.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..., in: line)
            ), match.numberOfRanges >= 3 {
                let severityStr = extractGroup(match, 1, from: line).lowercased()
                let message = extractGroup(match, 2, from: line)

                let diagnostic = BuildDiagnostic(
                    message: message,
                    file: nil,
                    line: nil,
                    column: nil,
                    severity: severityStr == "error" ? .error : .warning
                )

                if severityStr == "error" {
                    errors.append(diagnostic)
                } else {
                    warnings.append(diagnostic)
                }
                continue
            }

            // Pattern 3: Linker errors
            if let match = linkerErrorRegex?.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..., in: line)
            ), match.numberOfRanges >= 2 {
                let message = "ld: " + extractGroup(match, 1, from: line)

                let diagnostic = BuildDiagnostic(
                    message: message,
                    file: nil,
                    line: nil,
                    column: nil,
                    severity: .error
                )
                errors.append(diagnostic)
                continue
            }

            // Pattern 4: Clang errors
            if let match = clangErrorRegex?.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..., in: line)
            ), match.numberOfRanges >= 3 {
                let severityStr = extractGroup(match, 1, from: line).lowercased()
                let message = "clang: " + extractGroup(match, 2, from: line)

                let diagnostic = BuildDiagnostic(
                    message: message,
                    file: nil,
                    line: nil,
                    column: nil,
                    severity: severityStr == "error" ? .error : .warning
                )

                if severityStr == "error" {
                    errors.append(diagnostic)
                } else {
                    warnings.append(diagnostic)
                }
                continue
            }
        }

        // Add failed commands as errors if we captured any
        for command in failedCommands {
            let diagnostic = BuildDiagnostic(
                message: "Failed: \(command)",
                file: nil,
                line: nil,
                column: nil,
                severity: .error
            )
            errors.append(diagnostic)
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

        // Swift Testing framework format (new in Swift 6):
        // 􁁛  Test testName() passed after 0.008 seconds.
        // ✘  Test testName() failed after 0.008 seconds.
        // The emoji varies: 􁁛 (passed), ✘ (failed), ○ (skipped)
        let swiftTestingPattern = #"Test (\S+)\(\) (passed|failed|skipped) after ([\d.]+) seconds"#
        let swiftTestingRegex = try? NSRegularExpression(pattern: swiftTestingPattern, options: [])

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
            // Try Swift Testing framework format (Swift 6+)
            // Format: 􁁛  Test testName() passed after 0.008 seconds.
            else if let match = swiftTestingRegex?.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..., in: line)
            ), match.numberOfRanges >= 4 {
                let testName = extractGroup(match, 1, from: line)
                let statusStr = extractGroup(match, 2, from: line)
                let duration = Double(extractGroup(match, 3, from: line)) ?? 0

                let status: TestStatus
                switch statusStr {
                case "passed": status = .passed
                case "failed": status = .failed
                default: status = .skipped
                }

                let testCase = TestCase(
                    name: testName,
                    className: "SwiftTesting",
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

    // MARK: - Simctl Output Parsing

    /// Parse simctl list devices --json output
    static func parseSimulatorDevices(_ jsonString: String) throws -> [String: [SimulatorDevice]] {
        guard let data = jsonString.data(using: .utf8) else {
            return [:]
        }

        struct DevicesResponse: Decodable {
            let devices: [String: [SimulatorDevice]]
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(DevicesResponse.self, from: data)
        return response.devices
    }

    /// Parse simctl list runtimes --json output
    static func parseSimulatorRuntimes(_ jsonString: String) throws -> [SimulatorRuntime] {
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }

        struct RuntimesResponse: Decodable {
            let runtimes: [SimulatorRuntime]
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(RuntimesResponse.self, from: data)
        return response.runtimes
    }

    /// Parse simctl list devicetypes --json output
    static func parseSimulatorDeviceTypes(_ jsonString: String) throws -> [SimulatorDeviceType] {
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }

        struct DeviceTypesResponse: Decodable {
            let devicetypes: [SimulatorDeviceType]
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(DeviceTypesResponse.self, from: data)
        return response.devicetypes
    }

    /// Parse simctl list --json output (combined devices and runtimes)
    static func parseSimulatorList(_ jsonString: String) throws -> SimulatorListResult {
        guard let data = jsonString.data(using: .utf8) else {
            return SimulatorListResult(devices: [:], runtimes: nil)
        }

        struct ListResponse: Decodable {
            let devices: [String: [SimulatorDevice]]
            let runtimes: [SimulatorRuntime]?
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(ListResponse.self, from: data)
        return SimulatorListResult(devices: response.devices, runtimes: response.runtimes)
    }

    /// Parse simctl listapps output (plist format)
    static func parseInstalledApps(_ plistString: String) throws -> [InstalledApp] {
        guard let data = plistString.data(using: .utf8) else {
            return []
        }

        guard let plist = try PropertyListSerialization.propertyList(
            from: data,
            format: nil
        ) as? [String: [String: Any]] else {
            return []
        }

        return plist.compactMap { (bundleId, info) -> InstalledApp? in
            let name = info["CFBundleName"] as? String
                ?? info["CFBundleDisplayName"] as? String
                ?? bundleId
            let version = info["CFBundleShortVersionString"] as? String
            let applicationType = info["ApplicationType"] as? String ?? "User"

            return InstalledApp(
                bundleIdentifier: bundleId,
                name: name,
                version: version,
                applicationType: applicationType
            )
        }
    }

    /// Parse simctl appinfo output (key: value pairs)
    static func parseAppInfo(_ output: String) -> AppInfo? {
        var info: [String: String] = [:]
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                info[key] = value
            }
        }

        guard let bundleId = info["ApplicationIdentifier"]
            ?? info["CFBundleIdentifier"]
            ?? info["Bundle"] else {
            return nil
        }

        return AppInfo(
            bundleIdentifier: bundleId,
            name: info["CFBundleName"] ?? info["CFBundleDisplayName"],
            version: info["CFBundleShortVersionString"],
            bundleVersion: info["CFBundleVersion"],
            dataContainer: info["DataContainer"],
            bundlePath: info["Path"] ?? info["Bundle"],
            applicationType: info["ApplicationType"]
        )
    }

    /// Parse simctl launch output for PID
    static func parseLaunchPID(_ output: String) -> Int? {
        // Output format: "com.example.app: 12345"
        let parts = output.components(separatedBy: ":")
        if parts.count >= 2 {
            let pidString = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Int(pidString)
        }
        return nil
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
