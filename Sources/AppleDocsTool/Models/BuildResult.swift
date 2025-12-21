import Foundation

// MARK: - Diagnostic Types

/// Severity level for build diagnostics
enum DiagnosticSeverity: String, Codable, Sendable {
    case error
    case warning
    case note
}

/// A diagnostic message from build or test output
struct BuildDiagnostic: Codable, Sendable {
    let message: String
    let file: String?
    let line: Int?
    let column: Int?
    let severity: DiagnosticSeverity
}

// MARK: - Build Result

/// Result of a build operation
struct BuildResult: Codable, Sendable {
    let success: Bool
    let duration: TimeInterval
    let errors: [BuildDiagnostic]
    let warnings: [BuildDiagnostic]
    let buildLogPath: String?

    var summary: String {
        if success {
            if warnings.isEmpty {
                return "Build succeeded in \(String(format: "%.1f", duration))s"
            } else {
                return "Build succeeded with \(warnings.count) warning(s) in \(String(format: "%.1f", duration))s"
            }
        } else {
            return "Build failed with \(errors.count) error(s) in \(String(format: "%.1f", duration))s"
        }
    }
}

// MARK: - Test Result

/// Status of an individual test case
enum TestStatus: String, Codable, Sendable {
    case passed
    case failed
    case skipped
}

/// Result of a single test case
struct TestCase: Codable, Sendable {
    let name: String
    let className: String
    let duration: TimeInterval
    let status: TestStatus
    let failureMessage: String?
    let failureLocation: String?
}

/// Code coverage information
struct CodeCoverage: Codable, Sendable {
    let lineCoverage: Double  // 0.0 to 1.0
    let branchCoverage: Double?
    let functionCoverage: Double?
    let fileCoverage: [FileCoverage]?
}

/// Coverage for a single file
struct FileCoverage: Codable, Sendable {
    let path: String
    let lineCoverage: Double
    let coveredLines: Int
    let executableLines: Int
}

/// Result of a test operation
struct TestResult: Codable, Sendable {
    let success: Bool
    let duration: TimeInterval
    let totalTests: Int
    let passed: Int
    let failed: Int
    let skipped: Int
    let testCases: [TestCase]
    let codeCoverage: CodeCoverage?

    var summary: String {
        if success {
            return "All \(totalTests) test(s) passed in \(String(format: "%.1f", duration))s"
        } else {
            return "\(failed) of \(totalTests) test(s) failed in \(String(format: "%.1f", duration))s"
        }
    }
}

// MARK: - Run Result

/// Result of running an executable
struct RunResult: Codable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let duration: TimeInterval
    let wasTerminated: Bool

    var success: Bool {
        exitCode == 0 && !wasTerminated
    }

    var summary: String {
        if wasTerminated {
            return "Process was terminated after \(String(format: "%.1f", duration))s"
        } else if success {
            return "Process exited successfully in \(String(format: "%.1f", duration))s"
        } else {
            return "Process exited with code \(exitCode) in \(String(format: "%.1f", duration))s"
        }
    }
}

// MARK: - Profile Result

/// Summary of profiling data
struct ProfileSummary: Codable, Sendable {
    let topFunctions: [FunctionProfile]?
    let allocations: AllocationSummary?
    let leaks: [LeakInfo]?
}

/// Profile data for a function
struct FunctionProfile: Codable, Sendable {
    let name: String
    let selfTime: TimeInterval
    let totalTime: TimeInterval
    let callCount: Int?
}

/// Summary of memory allocations
struct AllocationSummary: Codable, Sendable {
    let totalAllocations: Int
    let totalBytes: Int
    let persistentBytes: Int?
}

/// Information about a memory leak
struct LeakInfo: Codable, Sendable {
    let address: String
    let size: Int
    let typeName: String?
    let backtrace: [String]?
}

/// Result of an Instruments profiling session
struct ProfileResult: Codable, Sendable {
    let tracePath: String
    let duration: TimeInterval
    let template: String
    let summary: ProfileSummary?

    var summaryText: String {
        "Recorded \(String(format: "%.1f", duration))s using \(template) template"
    }
}

// MARK: - Scheme and Destination Types

/// Information about an Xcode scheme
struct Scheme: Codable, Sendable {
    let name: String
    let isShared: Bool?
}

/// Available build destination
struct Destination: Codable, Sendable {
    let platform: String
    let name: String
    let id: String?
    let os: String?
    let arch: String?
}

/// Result of listing schemes
struct SchemesResult: Codable, Sendable {
    let projectPath: String
    let schemes: [Scheme]
}

/// Result of listing destinations
struct DestinationsResult: Codable, Sendable {
    let projectPath: String
    let scheme: String?
    let destinations: [Destination]
}

// MARK: - Instruments Template

/// Information about an Instruments template
struct InstrumentTemplate: Codable, Sendable {
    let name: String
    let category: String?
}

/// Result of listing Instruments templates
struct TemplatesResult: Codable, Sendable {
    let templates: [InstrumentTemplate]
}
