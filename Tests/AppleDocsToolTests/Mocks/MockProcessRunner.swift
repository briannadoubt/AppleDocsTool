import Foundation
@testable import AppleDocsToolCore

/// Protocol for process running to enable dependency injection in tests
/// NOTE: This is for future refactoring - currently services use ProcessRunner directly
protocol ProcessRunning: Sendable {
    func run(_ config: ProcessRunner.Configuration) async throws -> ProcessRunner.Result
    func swift(arguments: [String], workingDirectory: String?, timeout: TimeInterval) async throws -> ProcessRunner.Result
    func xcrun(arguments: [String], workingDirectory: String?, timeout: TimeInterval) async throws -> ProcessRunner.Result
    func xcodebuild(arguments: [String], workingDirectory: String?, timeout: TimeInterval) async throws -> ProcessRunner.Result
}

/// Mock process runner for unit testing
/// Allows setting predefined responses for specific command patterns
actor MockProcessRunner: ProcessRunning {

    /// A mock response for a command
    struct MockResponse: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String

        init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
        }

        static func success(_ stdout: String) -> MockResponse {
            MockResponse(stdout: stdout)
        }

        static func failure(_ stderr: String, exitCode: Int32 = 1) -> MockResponse {
            MockResponse(stderr: stderr, exitCode: exitCode)
        }
    }

    /// Recorded invocation
    struct Invocation: Sendable {
        let executable: String
        let arguments: [String]
        let timestamp: Date
    }

    private var responses: [String: MockResponse] = [:]
    private(set) var invocations: [Invocation] = []
    private var defaultResponse = MockResponse()

    /// Set a mock response for a command pattern
    /// - Parameters:
    ///   - pattern: The command pattern to match (e.g., "simctl list devices")
    ///   - response: The mock response to return
    func setResponse(for pattern: String, response: MockResponse) {
        responses[pattern] = response
    }

    /// Set the default response for unmatched commands
    func setDefaultResponse(_ response: MockResponse) {
        defaultResponse = response
    }

    /// Clear all recorded invocations
    func clearInvocations() {
        invocations = []
    }

    /// Get all invocations matching a pattern
    func invocations(matching pattern: String) -> [Invocation] {
        invocations.filter { inv in
            let fullCommand = ([inv.executable] + inv.arguments).joined(separator: " ")
            return fullCommand.contains(pattern)
        }
    }

    // MARK: - ProcessRunning Protocol

    func run(_ config: ProcessRunner.Configuration) async throws -> ProcessRunner.Result {
        let invocation = Invocation(
            executable: config.executable,
            arguments: config.arguments,
            timestamp: Date()
        )
        invocations.append(invocation)

        // Find matching response
        let fullCommand = ([config.executable] + config.arguments).joined(separator: " ")
        let response = responses.first { (pattern, _) in
            fullCommand.contains(pattern)
        }?.value ?? defaultResponse

        return ProcessRunner.Result(
            exitCode: response.exitCode,
            stdout: response.stdout,
            stderr: response.stderr,
            duration: 0.1,
            wasTerminated: false
        )
    }

    func swift(arguments: [String], workingDirectory: String?, timeout: TimeInterval) async throws -> ProcessRunner.Result {
        try await run(ProcessRunner.Configuration(
            executable: "/usr/bin/swift",
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeout: timeout
        ))
    }

    func xcrun(arguments: [String], workingDirectory: String?, timeout: TimeInterval) async throws -> ProcessRunner.Result {
        try await run(ProcessRunner.Configuration(
            executable: "/usr/bin/xcrun",
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeout: timeout
        ))
    }

    func xcodebuild(arguments: [String], workingDirectory: String?, timeout: TimeInterval) async throws -> ProcessRunner.Result {
        try await run(ProcessRunner.Configuration(
            executable: "/usr/bin/xcodebuild",
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeout: timeout
        ))
    }
}

// MARK: - Test Fixtures

/// Common simctl JSON fixtures for testing
enum SimctlFixtures {
    static let emptyDeviceList = """
    {
        "devices": {}
    }
    """

    static let singleDevice = """
    {
        "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
                {
                    "udid": "12345678-1234-1234-1234-123456789012",
                    "name": "iPhone 15",
                    "state": "Shutdown",
                    "isAvailable": true
                }
            ]
        }
    }
    """

    static let multipleDevices = """
    {
        "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
                {
                    "udid": "11111111-1111-1111-1111-111111111111",
                    "name": "iPhone 15",
                    "state": "Booted",
                    "isAvailable": true
                },
                {
                    "udid": "22222222-2222-2222-2222-222222222222",
                    "name": "iPhone 15 Pro",
                    "state": "Shutdown",
                    "isAvailable": true
                }
            ],
            "com.apple.CoreSimulator.SimRuntime.watchOS-10-0": [
                {
                    "udid": "33333333-3333-3333-3333-333333333333",
                    "name": "Apple Watch Series 9",
                    "state": "Shutdown",
                    "isAvailable": true
                }
            ]
        }
    }
    """

    static let runtimesList = """
    {
        "runtimes": [
            {
                "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
                "name": "iOS 17.0",
                "version": "17.0",
                "buildversion": "21A328",
                "isAvailable": true
            },
            {
                "identifier": "com.apple.CoreSimulator.SimRuntime.watchOS-10-0",
                "name": "watchOS 10.0",
                "version": "10.0",
                "buildversion": "21R355",
                "isAvailable": true
            }
        ]
    }
    """
}
