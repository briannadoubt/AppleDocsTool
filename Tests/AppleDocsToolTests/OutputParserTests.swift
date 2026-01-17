import Testing
@testable import AppleDocsToolCore

// MARK: - Build Output Parsing Tests

@Test func parseBuildOutputSingleError() {
    let output = "/path/to/File.swift:42:10: error: cannot find 'foo' in scope"
    let (errors, warnings) = OutputParser.parseBuildOutput(output)

    #expect(errors.count == 1)
    #expect(warnings.isEmpty)
    #expect(errors[0].file == "/path/to/File.swift")
    #expect(errors[0].line == 42)
    #expect(errors[0].column == 10)
    #expect(errors[0].message == "cannot find 'foo' in scope")
    #expect(errors[0].severity == .error)
}

@Test func parseBuildOutputSingleWarning() {
    let output = "/path/to/File.swift:15:5: warning: variable 'x' was never used"
    let (errors, warnings) = OutputParser.parseBuildOutput(output)

    #expect(errors.isEmpty)
    #expect(warnings.count == 1)
    #expect(warnings[0].file == "/path/to/File.swift")
    #expect(warnings[0].line == 15)
    #expect(warnings[0].column == 5)
    #expect(warnings[0].message == "variable 'x' was never used")
    #expect(warnings[0].severity == .warning)
}

@Test func parseBuildOutputMultipleIssues() {
    let output = """
    /path/File1.swift:10:1: error: missing return
    /path/File2.swift:20:3: warning: deprecated API
    /path/File1.swift:15:8: error: type mismatch
    /path/File3.swift:5:2: warning: unused variable
    """
    let (errors, warnings) = OutputParser.parseBuildOutput(output)

    #expect(errors.count == 2)
    #expect(warnings.count == 2)
}

@Test func parseBuildOutputNoIssues() {
    let output = """
    Building for debugging...
    Build complete!
    """
    let (errors, warnings) = OutputParser.parseBuildOutput(output)

    #expect(errors.isEmpty)
    #expect(warnings.isEmpty)
}

@Test func parseBuildOutputNoteIgnored() {
    let output = "/path/File.swift:10:1: note: did you mean 'bar'?"
    let (errors, warnings) = OutputParser.parseBuildOutput(output)

    #expect(errors.isEmpty)
    #expect(warnings.isEmpty)
}

@Test func parseBuildOutputMalformedLine() {
    let output = "This is not a valid diagnostic line"
    let (errors, warnings) = OutputParser.parseBuildOutput(output)

    #expect(errors.isEmpty)
    #expect(warnings.isEmpty)
}

// MARK: - Build Success Detection Tests

@Test func isBuildSuccessfulWithBuildComplete() {
    let output = """
    Building for debugging...
    [5/5] Linking MyApp
    Build complete!
    """
    #expect(OutputParser.isBuildSuccessful(output))
}

@Test func isBuildSuccessfulWithBuildSucceeded() {
    let output = """
    ** BUILD SUCCEEDED **
    """
    #expect(OutputParser.isBuildSuccessful(output))
}

@Test func isBuildSuccessfulWithError() {
    let output = """
    /path/File.swift:10:1: error: something went wrong
    """
    #expect(!OutputParser.isBuildSuccessful(output))
}

@Test func isBuildSuccessfulWithBuildFailed() {
    let output = """
    ** BUILD FAILED **
    """
    #expect(!OutputParser.isBuildSuccessful(output))
}

@Test func isBuildSuccessfulEmptyOutput() {
    let output = ""
    #expect(OutputParser.isBuildSuccessful(output))
}

// MARK: - Test Output Parsing Tests

@Test func parseTestOutputAllPassed() {
    let output = """
    Test Case '-[MyTests.FooTests testExample]' passed (0.001 seconds).
    Test Case '-[MyTests.FooTests testAnother]' passed (0.002 seconds).
    """
    let result = OutputParser.parseTestOutput(output)

    #expect(result.success)
    #expect(result.totalTests == 2)
    #expect(result.passed == 2)
    #expect(result.failed == 0)
    #expect(result.skipped == 0)
}

@Test func parseTestOutputSomeFailed() {
    let output = """
    Test Case '-[MyTests.FooTests testGood]' passed (0.001 seconds).
    /path/FooTests.swift:25: error: -[MyTests.FooTests testBad] : XCTAssertEqual failed
    Test Case '-[MyTests.FooTests testBad]' failed (0.003 seconds).
    """
    let result = OutputParser.parseTestOutput(output)

    #expect(!result.success)
    #expect(result.totalTests == 2)
    #expect(result.passed == 1)
    #expect(result.failed == 1)
}

@Test func parseTestOutputWithSkipped() {
    let output = """
    Test Case '-[MyTests.FooTests testSkipped]' skipped (0.000 seconds).
    Test Case '-[MyTests.FooTests testPassed]' passed (0.001 seconds).
    """
    let result = OutputParser.parseTestOutput(output)

    #expect(result.success)
    #expect(result.totalTests == 2)
    #expect(result.passed == 1)
    #expect(result.skipped == 1)
}

@Test func parseTestOutputSwiftFormat() {
    let output = """
    Test Case 'FooTests.testExample' passed (0.001 seconds).
    Test Case 'FooTests.testAnother' passed (0.002 seconds).
    """
    let result = OutputParser.parseTestOutput(output)

    #expect(result.success)
    #expect(result.totalTests == 2)
    #expect(result.passed == 2)
}

@Test func parseTestOutputWithFailureMessage() {
    let output = """
    /path/FooTests.swift:42: error: -[MyTests.FooTests testFail] : XCTAssertTrue failed
    Test Case '-[MyTests.FooTests testFail]' failed (0.001 seconds).
    """
    let result = OutputParser.parseTestOutput(output)

    #expect(!result.success)
    #expect(result.testCases.count == 1)
    #expect(result.testCases[0].failureMessage == "XCTAssertTrue failed")
    #expect(result.testCases[0].failureLocation == "/path/FooTests.swift:42")
}

@Test func parseTestOutputEmpty() {
    let output = ""
    let result = OutputParser.parseTestOutput(output)

    #expect(result.success)
    #expect(result.totalTests == 0)
}

@Test func parseTestOutputSwiftTestingFormat() {
    // Swift Testing framework format (Swift 6+)
    let output = """
    Test run started.
    Test parseSchemesListWorkspaceFormat() passed after 0.003 seconds.
    Test accessLevelFromSymbolGraph() passed after 0.002 seconds.
    Test searchExactMatch() failed after 0.003 seconds.
    Test run with 3 tests passed after 0.010 seconds.
    """
    let result = OutputParser.parseTestOutput(output)

    #expect(!result.success)  // One test failed
    #expect(result.totalTests == 3)
    #expect(result.passed == 2)
    #expect(result.failed == 1)
}

// MARK: - Schemes List Parsing Tests

@Test func parseSchemesListJsonFormat() {
    let output = """
    {
        "project": {
            "name": "MyApp",
            "schemes": ["MyApp", "MyAppTests", "MyAppUITests"]
        }
    }
    """
    let schemes = OutputParser.parseSchemesList(output)

    #expect(schemes.count == 3)
    #expect(schemes[0].name == "MyApp")
    #expect(schemes[1].name == "MyAppTests")
    #expect(schemes[2].name == "MyAppUITests")
}

@Test func parseSchemesListWorkspaceFormat() {
    let output = """
    {
        "workspace": {
            "name": "MyWorkspace",
            "schemes": ["App", "Framework"]
        }
    }
    """
    let schemes = OutputParser.parseSchemesList(output)

    #expect(schemes.count == 2)
    #expect(schemes[0].name == "App")
    #expect(schemes[1].name == "Framework")
}

@Test func parseSchemesListTextFallback() {
    let output = """
    Information about project "MyApp":
        Targets:
            MyApp
            MyAppTests

        Schemes:
            MyApp
            MyAppTests
    """
    let schemes = OutputParser.parseSchemesList(output)

    #expect(schemes.count == 2)
    #expect(schemes[0].name == "MyApp")
    #expect(schemes[1].name == "MyAppTests")
}

// MARK: - Destinations Parsing Tests

@Test func parseDestinationsValidFormat() {
    let output = """
    Available destinations for scheme "MyApp":
        { platform:iOS Simulator, id:12345678-1234-1234-1234-123456789012, OS:17.0, name:iPhone 15 }
        { platform:macOS, name:My Mac }
    """
    let destinations = OutputParser.parseDestinations(output)

    #expect(destinations.count == 2)
    #expect(destinations[0].platform == "iOS Simulator")
    #expect(destinations[0].name == "iPhone 15")
    #expect(destinations[0].os == "17.0")
    #expect(destinations[1].platform == "macOS")
    #expect(destinations[1].name == "My Mac")
}

// MARK: - Instruments Templates Parsing Tests

@Test func parseInstrumentsTemplates() {
    let output = """
    == Standard ==
    Activity Monitor
    Allocations
    Time Profiler

    == Custom ==
    My Custom Template
    """
    let templates = OutputParser.parseInstrumentsTemplates(output)

    #expect(templates.count == 4)
    #expect(templates[0].name == "Activity Monitor")
    #expect(templates[0].category == "Standard")
    #expect(templates[3].name == "My Custom Template")
    #expect(templates[3].category == "Custom")
}

// MARK: - Simulator Device Parsing Tests

@Test func parseSimulatorDevicesJson() throws {
    let json = """
    {
        "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
                {
                    "udid": "12345678-1234-1234-1234-123456789012",
                    "name": "iPhone 15",
                    "state": "Booted",
                    "isAvailable": true
                }
            ]
        }
    }
    """
    let devices = try OutputParser.parseSimulatorDevices(json)

    #expect(devices.count == 1)
    let iOSDevices = devices["com.apple.CoreSimulator.SimRuntime.iOS-17-0"]
    #expect(iOSDevices?.count == 1)
    #expect(iOSDevices?[0].name == "iPhone 15")
    #expect(iOSDevices?[0].state == .booted)
    #expect(iOSDevices?[0].isAvailable == true)
}

@Test func parseSimulatorDevicesBootedState() throws {
    let json = """
    {
        "devices": {
            "iOS-17": [
                {"udid": "1", "name": "Device1", "state": "Booted", "isAvailable": true},
                {"udid": "2", "name": "Device2", "state": "Shutdown", "isAvailable": true}
            ]
        }
    }
    """
    let devices = try OutputParser.parseSimulatorDevices(json)
    let list = devices["iOS-17"]!

    #expect(list[0].state == .booted)
    #expect(list[1].state == .shutdown)
}

@Test func parseSimulatorRuntimesJson() throws {
    let json = """
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
    let runtimes = try OutputParser.parseSimulatorRuntimes(json)

    #expect(runtimes.count == 2)
    #expect(runtimes[0].name == "iOS 17.0")
    #expect(runtimes[0].platform == .iOS)
    #expect(runtimes[1].name == "watchOS 10.0")
    #expect(runtimes[1].platform == .watchOS)
}

@Test func parseSimulatorListCombined() throws {
    let json = """
    {
        "devices": {
            "iOS-17": [
                {"udid": "1", "name": "iPhone", "state": "Booted", "isAvailable": true}
            ]
        },
        "runtimes": [
            {
                "identifier": "iOS-17",
                "name": "iOS 17",
                "version": "17.0",
                "buildversion": "21A",
                "isAvailable": true
            }
        ]
    }
    """
    let result = try OutputParser.parseSimulatorList(json)

    #expect(result.totalCount == 1)
    #expect(result.bootedCount == 1)
    #expect(result.runtimes?.count == 1)
}

// MARK: - App Info Parsing Tests

@Test func parseAppInfoKeyValuePairs() {
    let output = """
    ApplicationIdentifier: com.example.app
    CFBundleName: MyApp
    CFBundleShortVersionString: 1.0.0
    CFBundleVersion: 42
    DataContainer: /path/to/data
    Path: /path/to/bundle
    ApplicationType: User
    """
    let info = OutputParser.parseAppInfo(output)

    #expect(info != nil)
    #expect(info?.bundleIdentifier == "com.example.app")
    #expect(info?.name == "MyApp")
    #expect(info?.version == "1.0.0")
    #expect(info?.bundleVersion == "42")
    #expect(info?.dataContainer == "/path/to/data")
    #expect(info?.applicationType == "User")
}

@Test func parseAppInfoMissingFields() {
    let output = """
    CFBundleIdentifier: com.example.minimal
    """
    let info = OutputParser.parseAppInfo(output)

    #expect(info != nil)
    #expect(info?.bundleIdentifier == "com.example.minimal")
    #expect(info?.name == nil)
}

@Test func parseAppInfoInvalid() {
    let output = "Not a valid app info format"
    let info = OutputParser.parseAppInfo(output)

    #expect(info == nil)
}

// MARK: - Launch PID Parsing Tests

@Test func parseLaunchPIDValid() {
    let output = "com.example.app: 12345"
    let pid = OutputParser.parseLaunchPID(output)

    #expect(pid == 12345)
}

@Test func parseLaunchPIDWithWhitespace() {
    let output = "com.example.app: 67890\n"
    let pid = OutputParser.parseLaunchPID(output)

    #expect(pid == 67890)
}

@Test func parseLaunchPIDInvalid() {
    let output = "Not a valid launch output"
    let pid = OutputParser.parseLaunchPID(output)

    #expect(pid == nil)
}
