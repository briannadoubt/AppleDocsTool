import Foundation
import Testing
@testable import AppleDocsToolCore

// MARK: - Integration Tests (using real swift build/test)

/// Integration tests for BuildService
/// NOTE: Full build/test integration tests are slow and may timeout.
/// These are commented out for CI but can be run manually.

// Uncomment to run full integration tests manually:
// @Test(.disabled("Slow - run manually"))
// func swiftBuildSucceeds() async throws { ... }

@Test func swiftBuildNonExistentPath() async throws {
    let service = BuildService()

    do {
        _ = try await service.swiftBuild(
            at: "/nonexistent/path/to/project"
        )
        #expect(Bool(false), "Should have thrown an error")
    } catch {
        #expect(error is BuildService.BuildError)
    }
}

// MARK: - Error Type Tests

@Test func buildErrorDescriptions() {
    let errors: [(BuildService.BuildError, String)] = [
        (.projectNotFound("/path"), "Project not found at: /path"),
        (.buildFailed("compile error"), "Build failed: compile error"),
        (.testFailed("assertion"), "Tests failed: assertion"),
        (.runFailed("crash"), "Run failed: crash"),
        (.schemeNotFound("MyScheme"), "Scheme not found: MyScheme"),
        (.invalidProject("missing manifest"), "Invalid project: missing manifest"),
        (.timeout(60), "Operation timed out after 60 seconds")
    ]

    for (error, expected) in errors {
        #expect(error.errorDescription == expected)
    }
}

// MARK: - BuildResult Construction Tests

@Test func buildResultSuccessSummary() {
    let result = BuildResult(
        success: true,
        duration: 5.5,
        errors: [],
        warnings: [],
        buildLogPath: nil
    )

    #expect(result.success)
    #expect(result.summary == "Build succeeded in 5.5s")
}

@Test func buildResultWithWarningsSummary() {
    let warning = BuildDiagnostic(
        message: "unused variable",
        file: "/path/file.swift",
        line: 10,
        column: 5,
        severity: .warning
    )

    let result = BuildResult(
        success: true,
        duration: 3.2,
        errors: [],
        warnings: [warning, warning, warning],
        buildLogPath: nil
    )

    #expect(result.success)
    #expect(result.summary == "Build succeeded with 3 warning(s) in 3.2s")
}

@Test func buildResultFailureSummary() {
    let error = BuildDiagnostic(
        message: "type mismatch",
        file: "/path/file.swift",
        line: 20,
        column: 8,
        severity: .error
    )

    let result = BuildResult(
        success: false,
        duration: 2.0,
        errors: [error],
        warnings: [],
        buildLogPath: nil
    )

    #expect(!result.success)
    #expect(result.summary == "Build failed with 1 error(s) in 2.0s")
}

// MARK: - TestResult Construction Tests

@Test func testResultSuccessSummary() {
    let result = TestResult(
        success: true,
        duration: 15.0,
        totalTests: 100,
        passed: 100,
        failed: 0,
        skipped: 0,
        testCases: [],
        codeCoverage: nil
    )

    #expect(result.success)
    #expect(result.summary == "All 100 test(s) passed in 15.0s")
}

@Test func testResultFailureSummary() {
    let result = TestResult(
        success: false,
        duration: 8.0,
        totalTests: 50,
        passed: 45,
        failed: 5,
        skipped: 0,
        testCases: [],
        codeCoverage: nil
    )

    #expect(!result.success)
    #expect(result.summary == "5 of 50 test(s) failed in 8.0s")
}

// MARK: - RunResult Tests

@Test func runResultSuccessProperties() {
    let result = RunResult(
        exitCode: 0,
        stdout: "Hello, World!",
        stderr: "",
        duration: 0.5,
        wasTerminated: false
    )

    #expect(result.success)
    #expect(result.exitCode == 0)
    #expect(result.stdout == "Hello, World!")
    #expect(result.summary == "Process exited successfully in 0.5s")
}

@Test func runResultFailureProperties() {
    let result = RunResult(
        exitCode: 1,
        stdout: "",
        stderr: "Error: something went wrong",
        duration: 0.2,
        wasTerminated: false
    )

    #expect(!result.success)
    #expect(result.exitCode == 1)
    #expect(result.summary == "Process exited with code 1 in 0.2s")
}

@Test func runResultTerminatedProperties() {
    let result = RunResult(
        exitCode: 0,
        stdout: "",
        stderr: "",
        duration: 60.0,
        wasTerminated: true
    )

    #expect(!result.success)  // Terminated = not success even if exit code 0
    #expect(result.wasTerminated)
    #expect(result.summary == "Process was terminated after 60.0s")
}

// NOTE: Removed trivial struct property tests (destinationProperties, schemeProperties,
// diagnosticSeverityValues, buildDiagnosticProperties) - they only tested that Swift
// structs store values correctly, not actual application logic.
