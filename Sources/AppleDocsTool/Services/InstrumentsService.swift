import Foundation

/// Service for profiling applications with Instruments
actor InstrumentsService {
    private let fileManager = FileManager.default

    // MARK: - Error Types

    enum InstrumentsError: Error, LocalizedError {
        case templateNotFound(String)
        case targetNotFound(String)
        case recordingFailed(String)
        case xctraceNotAvailable
        case invalidOutput(String)

        var errorDescription: String? {
            switch self {
            case .templateNotFound(let name):
                return "Instruments template not found: \(name)"
            case .targetNotFound(let path):
                return "Target not found: \(path)"
            case .recordingFailed(let message):
                return "Recording failed: \(message)"
            case .xctraceNotAvailable:
                return "xctrace is not available. Make sure Xcode is installed."
            case .invalidOutput(let message):
                return "Invalid output: \(message)"
            }
        }
    }

    // MARK: - Template Operations

    /// List available Instruments templates
    func listTemplates() async throws -> [InstrumentTemplate] {
        let result = try await ProcessRunner.xcrun(
            arguments: ["xctrace", "list", "templates"],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw InstrumentsError.xctraceNotAvailable
        }

        return OutputParser.parseInstrumentsTemplates(result.stdout)
    }

    /// List available devices for profiling
    func listDevices() async throws -> [Device] {
        let result = try await ProcessRunner.xcrun(
            arguments: ["xctrace", "list", "devices"],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw InstrumentsError.xctraceNotAvailable
        }

        return parseDevices(result.stdout)
    }

    // MARK: - Profiling Operations

    /// Profile an application or executable
    func profile(
        target: String,
        template: String,
        duration: Int = 10,
        outputPath: String? = nil,
        device: String? = nil
    ) async throws -> ProfileResult {
        // Validate target exists (if it's a path)
        if target.hasPrefix("/") || target.hasPrefix(".") {
            guard fileManager.fileExists(atPath: target) else {
                throw InstrumentsError.targetNotFound(target)
            }
        }

        // Validate template exists
        let templates = try await listTemplates()
        let templateExists = templates.contains { $0.name.lowercased() == template.lowercased() }
        if !templateExists {
            // Try partial match
            let partialMatch = templates.first {
                $0.name.lowercased().contains(template.lowercased())
            }
            if partialMatch == nil {
                throw InstrumentsError.templateNotFound(template)
            }
        }

        // Determine output path
        let tracePath: String
        if let outputPath = outputPath {
            tracePath = outputPath
        } else {
            let tempDir = fileManager.temporaryDirectory
            let fileName = "profile_\(UUID().uuidString.prefix(8)).trace"
            tracePath = tempDir.appendingPathComponent(fileName).path
        }

        // Build xctrace command
        var args = [
            "xctrace", "record",
            "--template", template,
            "--output", tracePath,
            "--time-limit", "\(duration)s"
        ]

        if let device = device {
            args += ["--device", device]
        }

        // Determine how to specify the target
        if target.hasPrefix("/") {
            // It's an app bundle or executable path
            if target.hasSuffix(".app") {
                args += ["--launch", "--", target]
            } else {
                args += ["--launch", "--", target]
            }
        } else if Int(target) != nil {
            // It's a PID
            args += ["--attach", target]
        } else {
            // Assume it's an app name/bundle identifier
            args += ["--launch", "--", target]
        }

        let startTime = Date()
        let result = try await ProcessRunner.xcrun(
            arguments: args,
            timeout: TimeInterval(duration + 60)  // Extra time for startup/shutdown
        )

        let actualDuration = Date().timeIntervalSince(startTime)

        if result.exitCode != 0 && !fileManager.fileExists(atPath: tracePath) {
            throw InstrumentsError.recordingFailed(result.stderr)
        }

        // Try to get a summary from the trace
        let summary = try? await parseTraceSummary(at: tracePath, template: template)

        return ProfileResult(
            tracePath: tracePath,
            duration: actualDuration,
            template: template,
            summary: summary
        )
    }

    // MARK: - Trace Parsing

    /// Parse a trace file for summary information
    private func parseTraceSummary(at path: String, template: String) async throws -> ProfileSummary? {
        // Use xctrace export to get data
        let result = try await ProcessRunner.xcrun(
            arguments: ["xctrace", "export", "--input", path, "--toc"],
            timeout: 30
        )

        if result.exitCode != 0 {
            return nil
        }

        // The TOC gives us available tables
        // For now, return nil - full trace parsing would require
        // exporting specific tables and parsing their XML/JSON output
        return nil
    }

    // MARK: - Device Parsing

    private func parseDevices(_ output: String) -> [Device] {
        var devices: [Device] = []
        let lines = output.components(separatedBy: .newlines)

        // Pattern: DeviceName (version) (identifier)
        let devicePattern = #"^(.+?)\s+\(([^)]+)\)\s+\(([^)]+)\)$"#
        let deviceRegex = try? NSRegularExpression(pattern: devicePattern, options: [])

        // Simple pattern: DeviceName (identifier)
        let simplePattern = #"^(.+?)\s+\(([A-F0-9-]+)\)$"#
        let simpleRegex = try? NSRegularExpression(pattern: simplePattern, options: [])

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("==") {
                continue
            }

            // Try full pattern first
            if let match = deviceRegex?.firstMatch(
                in: trimmed,
                options: [],
                range: NSRange(trimmed.startIndex..., in: trimmed)
            ), match.numberOfRanges >= 4 {
                let name = extractGroup(match, 1, from: trimmed)
                let version = extractGroup(match, 2, from: trimmed)
                let id = extractGroup(match, 3, from: trimmed)

                devices.append(Device(
                    name: name,
                    identifier: id,
                    version: version,
                    platform: nil
                ))
            }
            // Try simple pattern
            else if let match = simpleRegex?.firstMatch(
                in: trimmed,
                options: [],
                range: NSRange(trimmed.startIndex..., in: trimmed)
            ), match.numberOfRanges >= 3 {
                let name = extractGroup(match, 1, from: trimmed)
                let id = extractGroup(match, 2, from: trimmed)

                devices.append(Device(
                    name: name,
                    identifier: id,
                    version: nil,
                    platform: nil
                ))
            }
        }

        return devices
    }

    private func extractGroup(_ match: NSTextCheckingResult, _ group: Int, from string: String) -> String {
        guard group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: string) else {
            return ""
        }
        return String(string[range])
    }
}

// MARK: - Device Model

/// Information about a device available for profiling
struct Device: Codable, Sendable {
    let name: String
    let identifier: String
    let version: String?
    let platform: String?
}
