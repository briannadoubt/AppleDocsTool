import Foundation
import Testing
@testable import AppleDocsToolCore

// MARK: - SymbolKind Tests

@Test func symbolKindFromSymbolGraphStruct() {
    let kind = SymbolKind(fromSymbolGraph: "swift.struct")
    #expect(kind == .struct)
}

@Test func symbolKindFromSymbolGraphClass() {
    let kind = SymbolKind(fromSymbolGraph: "swift.class")
    #expect(kind == .class)
}

@Test func symbolKindFromSymbolGraphEnum() {
    let kind = SymbolKind(fromSymbolGraph: "swift.enum")
    #expect(kind == .enum)
}

@Test func symbolKindFromSymbolGraphProtocol() {
    let kind = SymbolKind(fromSymbolGraph: "swift.protocol")
    #expect(kind == .protocol)
}

@Test func symbolKindFromSymbolGraphFunc() {
    #expect(SymbolKind(fromSymbolGraph: "swift.func") == .func)
    #expect(SymbolKind(fromSymbolGraph: "swift.method") == .func)
    #expect(SymbolKind(fromSymbolGraph: "swift.type.method") == .func)
    #expect(SymbolKind(fromSymbolGraph: "swift.func.op") == .func)
}

@Test func symbolKindFromSymbolGraphVar() {
    #expect(SymbolKind(fromSymbolGraph: "swift.var") == .var)
    #expect(SymbolKind(fromSymbolGraph: "swift.property") == .var)
    #expect(SymbolKind(fromSymbolGraph: "swift.type.property") == .var)
}

@Test func symbolKindFromSymbolGraphActor() {
    let kind = SymbolKind(fromSymbolGraph: "swift.actor")
    #expect(kind == .actor)
}

@Test func symbolKindFromSymbolGraphMacro() {
    let kind = SymbolKind(fromSymbolGraph: "swift.macro")
    #expect(kind == .macro)
}

@Test func symbolKindFromSymbolGraphUnknown() {
    let kind = SymbolKind(fromSymbolGraph: "swift.something.else")
    #expect(kind == .unknown)
}

// MARK: - AccessLevel Tests

@Test func accessLevelComparison() {
    #expect(AccessLevel.private < AccessLevel.fileprivate)
    #expect(AccessLevel.fileprivate < AccessLevel.internal)
    #expect(AccessLevel.internal < AccessLevel.package)
    #expect(AccessLevel.package < AccessLevel.public)
    #expect(AccessLevel.public < AccessLevel.open)
}

@Test func accessLevelNotLessThanSelf() {
    #expect(!(AccessLevel.public < AccessLevel.public))
}

@Test func accessLevelFromSymbolGraph() {
    #expect(AccessLevel(fromSymbolGraph: "private") == .private)
    #expect(AccessLevel(fromSymbolGraph: "fileprivate") == .fileprivate)
    #expect(AccessLevel(fromSymbolGraph: "internal") == .internal)
    #expect(AccessLevel(fromSymbolGraph: "package") == .package)
    #expect(AccessLevel(fromSymbolGraph: "public") == .public)
    #expect(AccessLevel(fromSymbolGraph: "open") == .open)
    #expect(AccessLevel(fromSymbolGraph: "unknown") == .internal)  // default
}

// MARK: - SimulatorPlatform Tests

@Test func simulatorPlatformFromRuntimeIdentifieriOS() {
    let platform = SimulatorPlatform.from(runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0")
    #expect(platform == .iOS)
}

@Test func simulatorPlatformFromRuntimeIdentifierwatchOS() {
    let platform = SimulatorPlatform.from(runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.watchOS-10-0")
    #expect(platform == .watchOS)
}

@Test func simulatorPlatformFromRuntimeIdentifiertvOS() {
    let platform = SimulatorPlatform.from(runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.tvOS-17-0")
    #expect(platform == .tvOS)
}

@Test func simulatorPlatformFromRuntimeIdentifiervisionOS() {
    let platform1 = SimulatorPlatform.from(runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.xrOS-1-0")
    let platform2 = SimulatorPlatform.from(runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.visionOS-2-0")
    #expect(platform1 == .visionOS)
    #expect(platform2 == .visionOS)
}

@Test func simulatorPlatformFromRuntimeIdentifierUnknown() {
    let platform = SimulatorPlatform.from(runtimeIdentifier: "unknown.runtime")
    #expect(platform == nil)
}

// MARK: - DeviceState Tests

@Test func deviceStateDecodingBooted() throws {
    let json = #"{"state": "Booted"}"#
    struct Container: Decodable { let state: DeviceState }
    let container = try JSONDecoder().decode(Container.self, from: json.data(using: .utf8)!)
    #expect(container.state == .booted)
}

@Test func deviceStateDecodingShutdown() throws {
    let json = #"{"state": "Shutdown"}"#
    struct Container: Decodable { let state: DeviceState }
    let container = try JSONDecoder().decode(Container.self, from: json.data(using: .utf8)!)
    #expect(container.state == .shutdown)
}

@Test func deviceStateDecodingUnknown() throws {
    let json = #"{"state": "SomethingElse"}"#
    struct Container: Decodable { let state: DeviceState }
    let container = try JSONDecoder().decode(Container.self, from: json.data(using: .utf8)!)
    #expect(container.state == .unknown)
}

// MARK: - BuildResult Tests

@Test func buildResultSummarySuccess() {
    let result = BuildResult(
        success: true,
        duration: 5.123,
        errors: [],
        warnings: [],
        buildLogPath: nil
    )
    #expect(result.summary == "Build succeeded in 5.1s")
}

@Test func buildResultSummarySuccessWithWarnings() {
    let warning = BuildDiagnostic(message: "warning", file: nil, line: nil, column: nil, severity: .warning)
    let result = BuildResult(
        success: true,
        duration: 3.0,
        errors: [],
        warnings: [warning, warning],
        buildLogPath: nil
    )
    #expect(result.summary == "Build succeeded with 2 warning(s) in 3.0s")
}

@Test func buildResultSummaryFailure() {
    let error = BuildDiagnostic(message: "error", file: nil, line: nil, column: nil, severity: .error)
    let result = BuildResult(
        success: false,
        duration: 2.5,
        errors: [error],
        warnings: [],
        buildLogPath: nil
    )
    #expect(result.summary == "Build failed with 1 error(s) in 2.5s")
}

// MARK: - TestResult Tests

@Test func testResultSummarySuccess() {
    let result = TestResult(
        success: true,
        duration: 10.5,
        totalTests: 42,
        passed: 42,
        failed: 0,
        skipped: 0,
        testCases: [],
        codeCoverage: nil
    )
    #expect(result.summary == "All 42 test(s) passed in 10.5s")
}

@Test func testResultSummaryFailure() {
    let result = TestResult(
        success: false,
        duration: 8.2,
        totalTests: 10,
        passed: 7,
        failed: 3,
        skipped: 0,
        testCases: [],
        codeCoverage: nil
    )
    #expect(result.summary == "3 of 10 test(s) failed in 8.2s")
}

// MARK: - RunResult Tests

@Test func runResultSuccess() {
    let result = RunResult(
        exitCode: 0,
        stdout: "output",
        stderr: "",
        duration: 1.0,
        wasTerminated: false
    )
    #expect(result.success)
    #expect(result.summary == "Process exited successfully in 1.0s")
}

@Test func runResultFailure() {
    let result = RunResult(
        exitCode: 1,
        stdout: "",
        stderr: "error",
        duration: 0.5,
        wasTerminated: false
    )
    #expect(!result.success)
    #expect(result.summary == "Process exited with code 1 in 0.5s")
}

@Test func runResultTerminated() {
    let result = RunResult(
        exitCode: 0,
        stdout: "",
        stderr: "",
        duration: 60.0,
        wasTerminated: true
    )
    #expect(!result.success)
    #expect(result.summary == "Process was terminated after 60.0s")
}

// MARK: - SimulatorListResult Tests

@Test func simulatorListResultCounts() {
    let device1 = SimulatorDevice(
        udid: "1", name: "iPhone", state: .booted, isAvailable: true,
        deviceTypeIdentifier: nil, dataPath: nil, logPath: nil, availabilityError: nil, lastBootedAt: nil
    )
    let device2 = SimulatorDevice(
        udid: "2", name: "iPad", state: .shutdown, isAvailable: true,
        deviceTypeIdentifier: nil, dataPath: nil, logPath: nil, availabilityError: nil, lastBootedAt: nil
    )
    let device3 = SimulatorDevice(
        udid: "3", name: "Watch", state: .shutdown, isAvailable: false,
        deviceTypeIdentifier: nil, dataPath: nil, logPath: nil, availabilityError: "Not available", lastBootedAt: nil
    )

    let result = SimulatorListResult(
        devices: ["iOS-17": [device1, device2], "watchOS-10": [device3]],
        runtimes: nil
    )

    #expect(result.totalCount == 3)
    #expect(result.bootedCount == 1)
    #expect(result.availableCount == 2)
    #expect(result.summary == "Found 3 devices (1 booted, 2 available)")
}

// MARK: - ProfileResult Tests

@Test func profileResultSummaryText() {
    let result = ProfileResult(
        tracePath: "/path/to/trace",
        duration: 30.5,
        template: "Time Profiler",
        summary: nil
    )
    #expect(result.summaryText == "Recorded 30.5s using Time Profiler template")
}

// MARK: - StatusBarOverrides Tests

@Test func statusBarOverridesToArguments() {
    var overrides = StatusBarOverrides()
    overrides.time = "9:41"
    overrides.batteryLevel = 100
    overrides.batteryState = "charged"
    overrides.cellularBars = 4
    overrides.operatorName = "Carrier"

    let args = overrides.toArguments()

    #expect(args.contains("--time"))
    #expect(args.contains("9:41"))
    #expect(args.contains("--batteryLevel"))
    #expect(args.contains("100"))
    #expect(args.contains("--batteryState"))
    #expect(args.contains("charged"))
    #expect(args.contains("--cellularBars"))
    #expect(args.contains("4"))
    #expect(args.contains("--operatorName"))
    #expect(args.contains("Carrier"))
}

@Test func statusBarOverridesEmptyArguments() {
    let overrides = StatusBarOverrides()
    let args = overrides.toArguments()
    #expect(args.isEmpty)
}

// MARK: - PushPayload Tests

@Test func pushPayloadWithAlert() throws {
    let payload = PushPayload(title: "Test", body: "Hello", badge: 5)
    let encoder = JSONEncoder()
    let data = try encoder.encode(payload)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    let aps = json["aps"] as! [String: Any]
    let alert = aps["alert"] as! [String: Any]

    #expect(alert["title"] as? String == "Test")
    #expect(alert["body"] as? String == "Hello")
    #expect(aps["badge"] as? Int == 5)
    #expect(aps["sound"] as? String == "default")
}

// MARK: - UIInteractionResult Tests

@Test func uiInteractionResultSummarySuccess() {
    let result = UIInteractionResult(
        success: true,
        action: "tap at (100, 200)",
        deviceName: "iPhone 15",
        message: nil
    )
    #expect(result.summary == "Successfully performed tap at (100, 200) on iPhone 15")
}

@Test func uiInteractionResultSummaryFailure() {
    let result = UIInteractionResult(
        success: false,
        action: "swipe",
        deviceName: nil,
        message: "Window not found"
    )
    #expect(result.summary == "Failed to perform swipe: Window not found")
}

// NOTE: Removed trivial raw value tests (hardwareButtonRawValues, privacyServiceRawValues)
// Testing `HardwareButton.home.rawValue == "home"` is just testing Swift's enum, not our code
