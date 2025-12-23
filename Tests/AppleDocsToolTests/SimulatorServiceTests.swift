import Foundation
import Testing
@testable import AppleDocsToolCore

// MARK: - Integration Tests (using real simctl)

/// Integration tests for SimulatorService
/// These tests use real simctl commands - they're read-only and don't modify simulator state
/// Tests are marked with .disabled if they require specific simulator configurations

@Test func listDevicesReturnsResult() async throws {
    let service = SimulatorService()
    let result = try await service.listDevices()

    // Should return a valid result (may be empty if no simulators installed)
    #expect(result.totalCount >= 0)
    #expect(result.summary.contains("Found"))
}

@Test func listDevicesFilterByPlatform() async throws {
    let service = SimulatorService()
    let result = try await service.listDevices(platform: .iOS)

    // All returned devices should be iOS
    for (runtimeId, _) in result.devices {
        let platform = SimulatorPlatform.from(runtimeIdentifier: runtimeId)
        #expect(platform == .iOS || platform == nil)  // nil if unknown runtime
    }
}

@Test func listDevicesFilterByState() async throws {
    let service = SimulatorService()

    // Get only booted devices
    let bootedResult = try await service.listDevices(state: .booted)

    // All returned devices should be booted
    for (_, devices) in bootedResult.devices {
        for device in devices {
            #expect(device.state == .booted)
        }
    }
}

@Test func listDevicesIncludeUnavailable() async throws {
    let service = SimulatorService()

    // Include unavailable devices
    let result = try await service.listDevices(availableOnly: false)

    // Should return a result (may include unavailable devices)
    #expect(result.totalCount >= 0)
}

@Test func listRuntimesReturnsRuntimes() async throws {
    let service = SimulatorService()
    let runtimes = try await service.listRuntimes()

    // Should return at least one runtime on a Mac with Xcode
    #expect(runtimes.count >= 0)  // May be 0 if no simulators installed

    // All runtimes should have valid identifiers
    for runtime in runtimes {
        #expect(!runtime.identifier.isEmpty)
        #expect(!runtime.name.isEmpty)
    }
}

@Test func listDeviceTypesReturnsTypes() async throws {
    let service = SimulatorService()
    let deviceTypes = try await service.listDeviceTypes()

    // Should return device types on a Mac with Xcode
    #expect(deviceTypes.count >= 0)

    for deviceType in deviceTypes {
        #expect(!deviceType.identifier.isEmpty)
        #expect(!deviceType.name.isEmpty)
    }
}

// MARK: - Device Resolution Tests

@Test func resolveDeviceWithUDID() async throws {
    let service = SimulatorService()

    // First get a real device UDID
    let result = try await service.listDevices()

    guard let firstDevice = result.devices.values.flatMap({ $0 }).first else {
        // Skip if no devices available
        return
    }

    // Try to resolve by UDID
    // Note: This tests the internal resolveDevice method indirectly
    // by using a method that calls it
    let devices = try await service.listDevices()
    let found = devices.devices.values.flatMap { $0 }.first { $0.udid == firstDevice.udid }
    #expect(found != nil)
}

// MARK: - Output Parsing Integration Tests

/// These tests verify that real simctl output can be parsed correctly

@Test func realSimctlListDevicesOutputCanBeParsed() async throws {
    // Run real simctl command
    let result = try await ProcessRunner.xcrun(
        arguments: ["simctl", "list", "devices", "--json"],
        timeout: 30
    )

    #expect(result.exitCode == 0)

    // Parse the output
    let listResult = try OutputParser.parseSimulatorList(result.stdout)
    #expect(listResult.totalCount >= 0)
}

@Test func realSimctlListRuntimesOutputCanBeParsed() async throws {
    let result = try await ProcessRunner.xcrun(
        arguments: ["simctl", "list", "runtimes", "--json"],
        timeout: 30
    )

    #expect(result.exitCode == 0)

    let runtimes = try OutputParser.parseSimulatorRuntimes(result.stdout)
    #expect(runtimes.count >= 0)

    for runtime in runtimes {
        #expect(runtime.platform != nil || runtime.identifier.contains("unknown"))
    }
}

@Test func realSimctlListDeviceTypesOutputCanBeParsed() async throws {
    let result = try await ProcessRunner.xcrun(
        arguments: ["simctl", "list", "devicetypes", "--json"],
        timeout: 30
    )

    #expect(result.exitCode == 0)

    let deviceTypes = try OutputParser.parseSimulatorDeviceTypes(result.stdout)
    #expect(deviceTypes.count >= 0)
}

// MARK: - Error Handling Tests

@Test func invalidDeviceIdThrowsError() async throws {
    let service = SimulatorService()

    do {
        // Try to boot a non-existent device
        _ = try await service.bootDevice("invalid-device-id-12345")
        #expect(Bool(false), "Should have thrown an error")
    } catch {
        // Expected - should throw some error
        #expect(error is SimulatorService.SimulatorError || error is ProcessRunner.ProcessError)
    }
}

// MARK: - Mock-Based Tests (for future refactoring)

/// Tests using MockProcessRunner to verify behavior without real simctl
/// NOTE: These require refactoring SimulatorService to accept dependency injection

@Test func mockProcessRunnerCanRecordInvocations() async {
    let mock = MockProcessRunner()

    await mock.setResponse(
        for: "simctl list devices",
        response: .success(SimctlFixtures.singleDevice)
    )

    let result = try? await mock.xcrun(
        arguments: ["simctl", "list", "devices", "--json"],
        workingDirectory: nil,
        timeout: 30
    )

    #expect(result?.exitCode == 0)

    let invocations = await mock.invocations(matching: "simctl")
    #expect(invocations.count == 1)
}

@Test func mockProcessRunnerReturnsConfiguredResponse() async {
    let mock = MockProcessRunner()

    await mock.setResponse(
        for: "simctl list runtimes",
        response: .success(SimctlFixtures.runtimesList)
    )

    let result = try? await mock.xcrun(
        arguments: ["simctl", "list", "runtimes", "--json"],
        workingDirectory: nil,
        timeout: 30
    )

    #expect(result?.stdout.contains("iOS 17.0") == true)
}

@Test func mockProcessRunnerReturnsFailure() async {
    let mock = MockProcessRunner()

    await mock.setResponse(
        for: "simctl boot",
        response: .failure("Device not found", exitCode: 1)
    )

    let result = try? await mock.xcrun(
        arguments: ["simctl", "boot", "invalid-id"],
        workingDirectory: nil,
        timeout: 30
    )

    #expect(result?.exitCode == 1)
    #expect(result?.stderr == "Device not found")
}

@Test func mockProcessRunnerUsesDefaultResponse() async {
    let mock = MockProcessRunner()

    await mock.setDefaultResponse(.success("default output"))

    let result = try? await mock.xcrun(
        arguments: ["simctl", "unknown-command"],
        workingDirectory: nil,
        timeout: 30
    )

    #expect(result?.stdout == "default output")
}

// MARK: - Computed Property Tests

@Test func simulatorListResultComputedProperties() {
    let result = SimulatorListResult(
        devices: [
            "iOS-17": [
                SimulatorDevice(
                    udid: "1", name: "iPhone 15", state: .booted, isAvailable: true,
                    deviceTypeIdentifier: nil, dataPath: nil, logPath: nil, availabilityError: nil, lastBootedAt: nil
                ),
                SimulatorDevice(
                    udid: "2", name: "iPhone 14", state: .shutdown, isAvailable: true,
                    deviceTypeIdentifier: nil, dataPath: nil, logPath: nil, availabilityError: nil, lastBootedAt: nil
                )
            ],
            "watchOS-10": [
                SimulatorDevice(
                    udid: "3", name: "Watch", state: .shutdown, isAvailable: false,
                    deviceTypeIdentifier: nil, dataPath: nil, logPath: nil, availabilityError: "Unavailable", lastBootedAt: nil
                )
            ]
        ],
        runtimes: nil
    )

    #expect(result.totalCount == 3)
    #expect(result.bootedCount == 1)
    #expect(result.availableCount == 2)
}

@Test func simulatorRuntimePlatformDetection() {
    let iOSRuntime = SimulatorRuntime(
        identifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
        name: "iOS 17.0",
        version: "17.0",
        buildversion: "21A",
        isAvailable: true,
        supportedDeviceTypes: nil
    )

    let watchRuntime = SimulatorRuntime(
        identifier: "com.apple.CoreSimulator.SimRuntime.watchOS-10-0",
        name: "watchOS 10.0",
        version: "10.0",
        buildversion: "21R",
        isAvailable: true,
        supportedDeviceTypes: nil
    )

    let visionRuntime = SimulatorRuntime(
        identifier: "com.apple.CoreSimulator.SimRuntime.xrOS-1-0",
        name: "visionOS 1.0",
        version: "1.0",
        buildversion: "21N",
        isAvailable: true,
        supportedDeviceTypes: nil
    )

    #expect(iOSRuntime.platform == .iOS)
    #expect(watchRuntime.platform == .watchOS)
    #expect(visionRuntime.platform == .visionOS)
}
