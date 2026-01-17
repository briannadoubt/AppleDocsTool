import Foundation
import MCP

/// MCP Server for Apple Documentation and Swift project symbols
public final class AppleDocsToolServer: @unchecked Sendable {
    private let server: Server
    private let symbolGraphService = SymbolGraphService()
    private let spmParser = SPMParser()
    private let xcodeParser = XcodeProjectParser()
    private let appleDocsService = AppleDocsService()
    private let localDocsService = LocalDocsService()
    private let dependencyService = DependencyService()
    private let gitHubDocsService = GitHubDocsService()
    private let searchService = SearchService()
    private let buildService = BuildService()
    private let instrumentsService = InstrumentsService()
    private let simulatorService = SimulatorService()
    private let simulatorUIService = SimulatorUIService()
    private let recordingManager = RecordingManager()

    public init() {
        self.server = Server(
            name: "apple-docs-tool",
            version: "1.0.0",
            capabilities: .init(
                tools: .init(listChanged: true)
            )
        )
    }

    public func start() async throws {
        await registerToolHandlers()

        let transport = StdioTransport()
        try await server.start(transport: transport)
    }

    private func registerToolHandlers() async {
        // Register tool listing handler
        await server.withMethodHandler(ListTools.self) { [weak self] _ in
            guard self != nil else { return .init(tools: []) }
            return .init(tools: Self.availableTools)
        }

        // Register tool call handler
        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self = self else {
                return .init(content: [.text("Server error")], isError: true)
            }
            return await self.handleToolCall(params)
        }
    }

    private static var availableTools: [Tool] {
        [
            Tool(
                name: "get_project_symbols",
                description: "Extract all symbols (types, functions, properties) from a Swift project (SPM package or Xcode project). Can include symbols from dependencies to prevent code duplication.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to Package.swift, .xcodeproj, or .xcworkspace")
                        ]),
                        "target": .object([
                            "type": .string("string"),
                            "description": .string("Specific target to analyze (optional, analyzes all targets if not specified)")
                        ]),
                        "minimum_access_level": .object([
                            "type": .string("string"),
                            "description": .string("Minimum access level to include: public, internal, private (default: public)"),
                            "enum": .array([.string("public"), .string("internal"), .string("private")])
                        ]),
                        "include_dependencies": .object([
                            "type": .string("boolean"),
                            "description": .string("Include symbols from package dependencies (default: false). Set to true to see all available APIs and avoid reimplementing existing functionality.")
                        ])
                    ]),
                    "required": .array([.string("project_path")])
                ])
            ),
            Tool(
                name: "get_project_dependencies",
                description: "List all dependencies for a Swift package, including versions, targets, and what each target depends on. Essential for understanding what libraries are available before writing code.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to Package.swift or directory containing it")
                        ]),
                        "include_symbols": .object([
                            "type": .string("boolean"),
                            "description": .string("Also extract public symbols from each dependency (default: false). Warning: can be slow for large dependency trees.")
                        ])
                    ]),
                    "required": .array([.string("project_path")])
                ])
            ),
            Tool(
                name: "get_symbol_documentation",
                description: "Get detailed documentation for a specific symbol in a Swift project",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to the Swift project")
                        ]),
                        "symbol_name": .object([
                            "type": .string("string"),
                            "description": .string("Fully qualified symbol name (e.g., MyModule.MyClass.myMethod)")
                        ])
                    ]),
                    "required": .array([.string("project_path"), .string("symbol_name")])
                ])
            ),
            Tool(
                name: "lookup_apple_api",
                description: "Fetch official Apple documentation for system frameworks. Note: Works best with symbol names (e.g., 'Chart', 'View'), not article URLs. Articles/tutorials may not be available via the JSON API.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "framework": .object([
                            "type": .string("string"),
                            "description": .string("Framework name (e.g., SwiftUI, Foundation, UIKit, Charts, Combine)")
                        ]),
                        "symbol": .object([
                            "type": .string("string"),
                            "description": .string("Specific symbol to look up (e.g., 'Chart', 'View', 'URLSession'). Use symbol names, not article titles.")
                        ]),
                        "url": .object([
                            "type": .string("string"),
                            "description": .string("Full Apple documentation URL (alternative to framework+symbol)")
                        ]),
                        "use_local": .object([
                            "type": .string("boolean"),
                            "description": .string("Prefer local Xcode docs over web (default: true)")
                        ])
                    ]),
                    "required": .array([])
                ])
            ),
            Tool(
                name: "search_symbols",
                description: "Search for symbols across a Swift project and/or Apple frameworks with fuzzy matching. Supports exact, prefix, camelCase, contains, and fuzzy matches with relevance ranking.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Search query - supports exact names, prefixes, camelCase (e.g., 'VM' finds 'ViewModel'), and fuzzy matching")
                        ]),
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to Swift project to include in search (optional)")
                        ]),
                        "frameworks": .object([
                            "type": .string("array"),
                            "description": .string("Apple frameworks to search (optional, searches common frameworks by default)"),
                            "items": .object(["type": .string("string")])
                        ]),
                        "max_results": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum number of results to return (default: 50)")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ])
            ),
            Tool(
                name: "get_dependency_docs",
                description: "Fetch documentation (README, guides) from a dependency's GitHub repository. Use this to understand how to use a third-party library.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to Swift project (to look up dependency URLs from Package.resolved)")
                        ]),
                        "dependency_name": .object([
                            "type": .string("string"),
                            "description": .string("Name of the dependency (e.g., 'Alamofire', 'swift-argument-parser')")
                        ]),
                        "github_url": .object([
                            "type": .string("string"),
                            "description": .string("Direct GitHub URL (alternative to project_path + dependency_name)")
                        ])
                    ]),
                    "required": .array([])
                ])
            ),
            Tool(
                name: "get_project_summary",
                description: "Get a quick overview of a Swift project: targets, dependencies, key types, and structure. Use this first when starting work on an unfamiliar project.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to Package.swift, .xcodeproj, or directory containing them")
                        ])
                    ]),
                    "required": .array([.string("project_path")])
                ])
            ),

            // MARK: - Build, Test, Run Tools

            Tool(
                name: "swift_build",
                description: "Build a Swift package using swift build. Returns structured JSON with build status, errors, warnings, and duration.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to Package.swift or directory containing it")
                        ]),
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string("Build configuration: 'debug' or 'release' (default: 'debug')"),
                            "enum": .array([.string("debug"), .string("release")])
                        ]),
                        "target": .object([
                            "type": .string("string"),
                            "description": .string("Specific target to build (optional, builds all if not specified)")
                        ]),
                        "clean": .object([
                            "type": .string("boolean"),
                            "description": .string("Clean before building (default: false)")
                        ])
                    ]),
                    "required": .array([.string("project_path")])
                ])
            ),
            Tool(
                name: "swift_test",
                description: "Run Swift package tests using swift test. Returns structured JSON with test results including passed, failed, skipped counts and individual test case details.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to Package.swift or directory containing it")
                        ]),
                        "filter": .object([
                            "type": .string("string"),
                            "description": .string("Test filter pattern (e.g., 'MyTests.testFoo' or 'MyTests')")
                        ]),
                        "parallel": .object([
                            "type": .string("boolean"),
                            "description": .string("Run tests in parallel (default: true)")
                        ]),
                        "enable_code_coverage": .object([
                            "type": .string("boolean"),
                            "description": .string("Enable code coverage (default: false)")
                        ])
                    ]),
                    "required": .array([.string("project_path")])
                ])
            ),
            Tool(
                name: "swift_run",
                description: "Run a Swift package executable using swift run. Returns stdout, stderr, exit code, and duration.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to Package.swift or directory containing it")
                        ]),
                        "executable": .object([
                            "type": .string("string"),
                            "description": .string("Name of the executable to run (optional, uses first executable)")
                        ]),
                        "arguments": .object([
                            "type": .string("array"),
                            "description": .string("Arguments to pass to the executable"),
                            "items": .object(["type": .string("string")])
                        ]),
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string("Build configuration: 'debug' or 'release' (default: 'debug')"),
                            "enum": .array([.string("debug"), .string("release")])
                        ]),
                        "timeout": .object([
                            "type": .string("integer"),
                            "description": .string("Timeout in seconds (default: 60)")
                        ])
                    ]),
                    "required": .array([.string("project_path")])
                ])
            ),
            Tool(
                name: "xcodebuild_build",
                description: "Build an Xcode project or workspace using xcodebuild. Returns structured JSON with build status, errors, warnings, and duration.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to .xcodeproj, .xcworkspace, or directory containing them")
                        ]),
                        "scheme": .object([
                            "type": .string("string"),
                            "description": .string("Scheme name (auto-detected if not provided)")
                        ]),
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string("Build configuration: 'Debug' or 'Release' (default: 'Debug')")
                        ]),
                        "destination": .object([
                            "type": .string("string"),
                            "description": .string("Full destination specifier (e.g., 'platform=iOS Simulator,name=iPhone 16')")
                        ]),
                        "destination_platform": .object([
                            "type": .string("string"),
                            "description": .string("Platform shorthand: 'iOS Simulator', 'macOS', 'tvOS Simulator', 'watchOS Simulator', 'iOS', 'tvOS', 'watchOS', 'visionOS Simulator'")
                        ]),
                        "clean": .object([
                            "type": .string("boolean"),
                            "description": .string("Clean before building (default: false)")
                        ])
                    ]),
                    "required": .array([.string("project_path")])
                ])
            ),
            Tool(
                name: "xcodebuild_test",
                description: "Run Xcode project tests using xcodebuild test. Returns structured JSON with test results.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to .xcodeproj, .xcworkspace, or directory containing them")
                        ]),
                        "scheme": .object([
                            "type": .string("string"),
                            "description": .string("Scheme name (auto-detected if not provided)")
                        ]),
                        "destination": .object([
                            "type": .string("string"),
                            "description": .string("Full destination specifier")
                        ]),
                        "destination_platform": .object([
                            "type": .string("string"),
                            "description": .string("Platform shorthand for destination")
                        ]),
                        "test_plan": .object([
                            "type": .string("string"),
                            "description": .string("Test plan name")
                        ]),
                        "only_testing": .object([
                            "type": .string("array"),
                            "description": .string("Specific tests to run (e.g., 'MyTests/testFoo')"),
                            "items": .object(["type": .string("string")])
                        ]),
                        "skip_testing": .object([
                            "type": .string("array"),
                            "description": .string("Tests to skip"),
                            "items": .object(["type": .string("string")])
                        ]),
                        "enable_code_coverage": .object([
                            "type": .string("boolean"),
                            "description": .string("Enable code coverage (default: false)")
                        ])
                    ]),
                    "required": .array([.string("project_path")])
                ])
            ),
            Tool(
                name: "list_schemes",
                description: "List available schemes for an Xcode project or Swift package.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to .xcodeproj, .xcworkspace, or Package.swift")
                        ])
                    ]),
                    "required": .array([.string("project_path")])
                ])
            ),
            Tool(
                name: "list_destinations",
                description: "List available build destinations for a project (simulators, devices, etc.).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to .xcodeproj or .xcworkspace")
                        ]),
                        "scheme": .object([
                            "type": .string("string"),
                            "description": .string("Scheme to get destinations for")
                        ]),
                        "platform": .object([
                            "type": .string("string"),
                            "description": .string("Filter by platform: 'iOS', 'macOS', 'tvOS', 'watchOS', 'visionOS'")
                        ])
                    ]),
                    "required": .array([.string("project_path")])
                ])
            ),
            Tool(
                name: "instruments_profile",
                description: "Profile an application using Instruments. Supports any Instruments template (Time Profiler, Allocations, Leaks, etc.).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "target": .object([
                            "type": .string("string"),
                            "description": .string("Path to app bundle, executable, or process ID to profile")
                        ]),
                        "template": .object([
                            "type": .string("string"),
                            "description": .string("Instruments template name (e.g., 'Time Profiler', 'Allocations', 'Leaks', 'App Launch')")
                        ]),
                        "duration": .object([
                            "type": .string("integer"),
                            "description": .string("Recording duration in seconds (default: 10)")
                        ]),
                        "output_path": .object([
                            "type": .string("string"),
                            "description": .string("Output path for .trace file (optional)")
                        ]),
                        "device": .object([
                            "type": .string("string"),
                            "description": .string("Device identifier for iOS/watchOS apps")
                        ])
                    ]),
                    "required": .array([.string("target"), .string("template")])
                ])
            ),
            Tool(
                name: "list_instruments_templates",
                description: "List available Instruments profiling templates.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "required": .array([])
                ])
            ),

            // MARK: - Simulator Tools (simctl)

            Tool(
                name: "simctl_list_devices",
                description: "List iOS/watchOS/tvOS/visionOS simulator devices with optional platform and state filters.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "platform": .object([
                            "type": .string("string"),
                            "description": .string("Filter by platform: iOS, watchOS, tvOS, visionOS"),
                            "enum": .array([.string("iOS"), .string("watchOS"), .string("tvOS"), .string("visionOS")])
                        ]),
                        "state": .object([
                            "type": .string("string"),
                            "description": .string("Filter by state: Booted, Shutdown"),
                            "enum": .array([.string("Booted"), .string("Shutdown")])
                        ]),
                        "available_only": .object([
                            "type": .string("boolean"),
                            "description": .string("Only show available devices (default: true)")
                        ])
                    ]),
                    "required": .array([])
                ])
            ),
            Tool(
                name: "simctl_list_runtimes",
                description: "List available simulator runtimes (iOS versions, etc.).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "platform": .object([
                            "type": .string("string"),
                            "description": .string("Filter by platform: iOS, watchOS, tvOS, visionOS"),
                            "enum": .array([.string("iOS"), .string("watchOS"), .string("tvOS"), .string("visionOS")])
                        ])
                    ]),
                    "required": .array([])
                ])
            ),
            Tool(
                name: "simctl_device_control",
                description: "Control simulator device lifecycle: boot, shutdown, create, delete, erase, or clone a device.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "description": .string("Action to perform"),
                            "enum": .array([.string("boot"), .string("shutdown"), .string("create"), .string("delete"), .string("erase"), .string("clone")])
                        ]),
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted' (required for boot/shutdown/delete/erase/clone)")
                        ]),
                        "device_name": .object([
                            "type": .string("string"),
                            "description": .string("Name for new device (required for create, optional for clone)")
                        ]),
                        "device_type": .object([
                            "type": .string("string"),
                            "description": .string("Device type identifier for create (e.g., 'iPhone 16 Pro')")
                        ]),
                        "runtime": .object([
                            "type": .string("string"),
                            "description": .string("Runtime identifier for create (e.g., 'iOS 18.0')")
                        ])
                    ]),
                    "required": .array([.string("action")])
                ])
            ),
            Tool(
                name: "simctl_app_install",
                description: "Install an app bundle (.app) on a simulator.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted'")
                        ]),
                        "app_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to the .app bundle to install")
                        ])
                    ]),
                    "required": .array([.string("device_id"), .string("app_path")])
                ])
            ),
            Tool(
                name: "simctl_app_control",
                description: "Control app lifecycle: launch, terminate, or uninstall an app.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "description": .string("Action to perform"),
                            "enum": .array([.string("launch"), .string("terminate"), .string("uninstall")])
                        ]),
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted'")
                        ]),
                        "bundle_id": .object([
                            "type": .string("string"),
                            "description": .string("App bundle identifier (e.g., 'com.apple.mobilesafari')")
                        ]),
                        "arguments": .object([
                            "type": .string("array"),
                            "description": .string("Launch arguments (for launch action only)"),
                            "items": .object(["type": .string("string")])
                        ]),
                        "wait_for_debugger": .object([
                            "type": .string("boolean"),
                            "description": .string("Wait for debugger to attach (for launch action)")
                        ])
                    ]),
                    "required": .array([.string("action"), .string("device_id"), .string("bundle_id")])
                ])
            ),
            Tool(
                name: "simctl_app_info",
                description: "Get information about an installed app or list all installed apps.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted'")
                        ]),
                        "bundle_id": .object([
                            "type": .string("string"),
                            "description": .string("App bundle identifier (omit to list all apps)")
                        ])
                    ]),
                    "required": .array([.string("device_id")])
                ])
            ),
            Tool(
                name: "simctl_screenshot",
                description: "Take a screenshot of the simulator.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted'")
                        ]),
                        "output_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to save screenshot (default: auto-generated in temp)")
                        ]),
                        "format": .object([
                            "type": .string("string"),
                            "description": .string("Image format"),
                            "enum": .array([.string("png"), .string("jpeg"), .string("tiff"), .string("bmp"), .string("gif")])
                        ]),
                        "mask": .object([
                            "type": .string("string"),
                            "description": .string("Mask policy for device frame"),
                            "enum": .array([.string("ignored"), .string("alpha"), .string("black")])
                        ])
                    ]),
                    "required": .array([.string("device_id")])
                ])
            ),
            Tool(
                name: "simctl_record_video",
                description: "Start or stop video recording of the simulator.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "description": .string("Action: start or stop"),
                            "enum": .array([.string("start"), .string("stop")])
                        ]),
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted'")
                        ]),
                        "output_path": .object([
                            "type": .string("string"),
                            "description": .string("Path to save video (required for start)")
                        ]),
                        "codec": .object([
                            "type": .string("string"),
                            "description": .string("Video codec"),
                            "enum": .array([.string("h264"), .string("hevc")])
                        ]),
                        "recording_id": .object([
                            "type": .string("string"),
                            "description": .string("Recording ID to stop (required for stop action)")
                        ])
                    ]),
                    "required": .array([.string("action"), .string("device_id")])
                ])
            ),
            Tool(
                name: "simctl_location",
                description: "Set or clear location on the simulator.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "description": .string("Action to perform"),
                            "enum": .array([.string("set"), .string("clear")])
                        ]),
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted'")
                        ]),
                        "latitude": .object([
                            "type": .string("number"),
                            "description": .string("Latitude for set action")
                        ]),
                        "longitude": .object([
                            "type": .string("number"),
                            "description": .string("Longitude for set action")
                        ])
                    ]),
                    "required": .array([.string("action"), .string("device_id")])
                ])
            ),
            Tool(
                name: "simctl_push",
                description: "Send a push notification to the simulator.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted'")
                        ]),
                        "bundle_id": .object([
                            "type": .string("string"),
                            "description": .string("Target app bundle identifier")
                        ]),
                        "title": .object([
                            "type": .string("string"),
                            "description": .string("Notification title")
                        ]),
                        "body": .object([
                            "type": .string("string"),
                            "description": .string("Notification body text")
                        ]),
                        "subtitle": .object([
                            "type": .string("string"),
                            "description": .string("Notification subtitle")
                        ]),
                        "badge": .object([
                            "type": .string("integer"),
                            "description": .string("Badge number")
                        ])
                    ]),
                    "required": .array([.string("device_id"), .string("bundle_id")])
                ])
            ),
            Tool(
                name: "simctl_privacy",
                description: "Grant, revoke, or reset privacy permissions for an app.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "description": .string("Action: grant, revoke, or reset"),
                            "enum": .array([.string("grant"), .string("revoke"), .string("reset")])
                        ]),
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted'")
                        ]),
                        "bundle_id": .object([
                            "type": .string("string"),
                            "description": .string("Target app bundle identifier")
                        ]),
                        "service": .object([
                            "type": .string("string"),
                            "description": .string("Privacy service: all, calendar, contacts, location, photos, camera, microphone, etc.")
                        ])
                    ]),
                    "required": .array([.string("action"), .string("device_id"), .string("bundle_id"), .string("service")])
                ])
            ),
            Tool(
                name: "simctl_status_bar",
                description: "Override simulator status bar appearance (time, battery, network, etc.).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "description": .string("Action: override or clear"),
                            "enum": .array([.string("override"), .string("clear")])
                        ]),
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted'")
                        ]),
                        "time": .object([
                            "type": .string("string"),
                            "description": .string("Time to display (e.g., '9:41')")
                        ]),
                        "battery_level": .object([
                            "type": .string("integer"),
                            "description": .string("Battery level 0-100")
                        ]),
                        "battery_state": .object([
                            "type": .string("string"),
                            "description": .string("Battery state: charging, charged, discharging")
                        ]),
                        "wifi_bars": .object([
                            "type": .string("integer"),
                            "description": .string("WiFi signal bars 0-3")
                        ]),
                        "cellular_bars": .object([
                            "type": .string("integer"),
                            "description": .string("Cellular signal bars 0-4")
                        ]),
                        "operator_name": .object([
                            "type": .string("string"),
                            "description": .string("Carrier name to display")
                        ])
                    ]),
                    "required": .array([.string("action"), .string("device_id")])
                ])
            ),
            Tool(
                name: "simctl_pasteboard",
                description: "Get or set the simulator pasteboard (clipboard) content.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "description": .string("Action: get or set"),
                            "enum": .array([.string("get"), .string("set")])
                        ]),
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted'")
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("Content to set (required for set action)")
                        ])
                    ]),
                    "required": .array([.string("action"), .string("device_id")])
                ])
            ),
            Tool(
                name: "simctl_open_url",
                description: "Open a URL in the simulator (for deep linking, universal links, etc.).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID, name, or 'booted'")
                        ]),
                        "url": .object([
                            "type": .string("string"),
                            "description": .string("URL to open (http://, https://, or custom scheme)")
                        ])
                    ]),
                    "required": .array([.string("device_id"), .string("url")])
                ])
            ),

            // MARK: - Simulator UI Tools (Consolidated)

            Tool(
                name: "simulator_ui_state",
                description: """
                    Get the current simulator UI state including screenshot and all visible text with coordinates.

                    **IMPORTANT: Call this FIRST before any simulator interaction to understand what's on screen.**

                    This tool:
                    1. Takes a screenshot of the simulator
                    2. Runs OCR to find all visible text
                    3. Returns text elements with their tap coordinates

                    **Workflow:**
                    1. Call simulator_ui_state to see what's on screen
                    2. Find the text/button you want to interact with
                    3. Use simulator_interact with the coordinates from step 1

                    Returns device info, screenshot path, and all visible text with (x, y) coordinates.
                    Requires: Simulator running, Accessibility permission for terminal app.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID or 'booted' for the active simulator (default: booted)")
                        ])
                    ]),
                    "required": .array([])
                ])
            ),
            Tool(
                name: "simulator_interact",
                description: """
                    Interact with the iOS Simulator: tap, swipe, type text, or press hardware buttons.

                    **Coordinates:** Use (x, y) in iOS points. Origin (0,0) is top-left.
                    Common device sizes: iPhone 16 is 393×852 points, iPhone 16 Pro Max is 440×956 points.

                    **Tip:** Call simulator_ui_state first to get coordinates of visible text elements.

                    **Actions:**
                    - tap: Single tap at (x, y)
                    - double_tap: Double tap at (x, y)
                    - long_press: Long press at (x, y) for specified duration
                    - swipe: Drag from (x, y) to (to_x, to_y)
                    - type: Type text (requires a focused text field)
                    - button: Press hardware button (home, lock, volumeUp, volumeDown, keyboard)

                    Requires: Accessibility permission for terminal app.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "description": .string("The interaction type"),
                            "enum": .array([.string("tap"), .string("double_tap"), .string("long_press"), .string("swipe"), .string("type"), .string("button")])
                        ]),
                        "x": .object([
                            "type": .string("integer"),
                            "description": .string("X coordinate for tap/swipe start (iOS points, 0 = left edge)")
                        ]),
                        "y": .object([
                            "type": .string("integer"),
                            "description": .string("Y coordinate for tap/swipe start (iOS points, 0 = top edge)")
                        ]),
                        "to_x": .object([
                            "type": .string("integer"),
                            "description": .string("End X coordinate for swipe")
                        ]),
                        "to_y": .object([
                            "type": .string("integer"),
                            "description": .string("End Y coordinate for swipe")
                        ]),
                        "text": .object([
                            "type": .string("string"),
                            "description": .string("Text to type (for 'type' action)")
                        ]),
                        "button": .object([
                            "type": .string("string"),
                            "description": .string("Hardware button (for 'button' action)"),
                            "enum": .array([.string("home"), .string("lock"), .string("volumeUp"), .string("volumeDown"), .string("ringer"), .string("screenshot"), .string("keyboard")])
                        ]),
                        "duration": .object([
                            "type": .string("number"),
                            "description": .string("Duration in seconds for long_press (default: 1.0) or swipe (default: 0.3)")
                        ]),
                        "device_name": .object([
                            "type": .string("string"),
                            "description": .string("Target simulator device name (optional, uses first found)")
                        ])
                    ]),
                    "required": .array([.string("action")])
                ])
            ),
            Tool(
                name: "simulator_find_text",
                description: """
                    Find text on the simulator screen and return its coordinates for tapping.

                    Takes a screenshot, runs OCR, and searches for the specified text.
                    Returns the center (x, y) coordinates if found, which you can pass to simulator_interact.

                    **Example workflow:**
                    1. simulator_find_text(text: "Login") → returns {x: 197, y: 445}
                    2. simulator_interact(action: "tap", x: 197, y: 445)

                    Matching: Case-insensitive by default. Tries exact match first, then substring match.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "text": .object([
                            "type": .string("string"),
                            "description": .string("The text to find on screen")
                        ]),
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Device UDID or 'booted' (default: booted)")
                        ]),
                        "case_sensitive": .object([
                            "type": .string("boolean"),
                            "description": .string("Whether to match case exactly (default: false)")
                        ])
                    ]),
                    "required": .array([.string("text")])
                ])
            )
        ]
    }

    private func handleToolCall(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            switch params.name {
            case "get_project_symbols":
                return try await handleGetProjectSymbols(params.arguments)

            case "get_project_dependencies":
                return try await handleGetProjectDependencies(params.arguments)

            case "get_symbol_documentation":
                return try await handleGetSymbolDocumentation(params.arguments)

            case "lookup_apple_api":
                return try await handleLookupAppleAPI(params.arguments)

            case "search_symbols":
                return try await handleSearchSymbols(params.arguments)

            case "get_dependency_docs":
                return try await handleGetDependencyDocs(params.arguments)

            case "get_project_summary":
                return try await handleGetProjectSummary(params.arguments)

            // Build, Test, Run tools
            case "swift_build":
                return try await handleSwiftBuild(params.arguments)

            case "swift_test":
                return try await handleSwiftTest(params.arguments)

            case "swift_run":
                return try await handleSwiftRun(params.arguments)

            case "xcodebuild_build":
                return try await handleXcodebuildBuild(params.arguments)

            case "xcodebuild_test":
                return try await handleXcodebuildTest(params.arguments)

            case "list_schemes":
                return try await handleListSchemes(params.arguments)

            case "list_destinations":
                return try await handleListDestinations(params.arguments)

            case "instruments_profile":
                return try await handleInstrumentsProfile(params.arguments)

            case "list_instruments_templates":
                return try await handleListInstrumentsTemplates(params.arguments)

            // Simulator tools (simctl)
            case "simctl_list_devices":
                return try await handleSimctlListDevices(params.arguments)

            case "simctl_list_runtimes":
                return try await handleSimctlListRuntimes(params.arguments)

            case "simctl_device_control":
                return try await handleSimctlDeviceControl(params.arguments)

            case "simctl_app_install":
                return try await handleSimctlAppInstall(params.arguments)

            case "simctl_app_control":
                return try await handleSimctlAppControl(params.arguments)

            case "simctl_app_info":
                return try await handleSimctlAppInfo(params.arguments)

            case "simctl_screenshot":
                return try await handleSimctlScreenshot(params.arguments)

            case "simctl_record_video":
                return try await handleSimctlRecordVideo(params.arguments)

            case "simctl_location":
                return try await handleSimctlLocation(params.arguments)

            case "simctl_push":
                return try await handleSimctlPush(params.arguments)

            case "simctl_privacy":
                return try await handleSimctlPrivacy(params.arguments)

            case "simctl_status_bar":
                return try await handleSimctlStatusBar(params.arguments)

            case "simctl_pasteboard":
                return try await handleSimctlPasteboard(params.arguments)

            case "simctl_open_url":
                return try await handleSimctlOpenURL(params.arguments)

            // Simulator UI tools (Consolidated)
            case "simulator_ui_state":
                return try await handleSimulatorUIState(params.arguments)

            case "simulator_interact":
                return try await handleSimulatorInteract(params.arguments)

            case "simulator_find_text":
                return try await handleSimulatorFindText(params.arguments)

            default:
                return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
            }
        } catch {
            return .init(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    // MARK: - Helper Methods

    /// Extract symbols using the appropriate method based on project type
    private func extractSymbols(
        from project: Project,
        targetName: String,
        minimumAccessLevel: AccessLevel
    ) async throws -> [Symbol] {
        switch project.type {
        case .xcode, .xcworkspace:
            return try await symbolGraphService.extractFromXcodeProject(
                at: project.path,
                targetName: targetName,
                minimumAccessLevel: minimumAccessLevel
            )
        case .spm:
            return try await symbolGraphService.extractFromPackage(
                at: project.path,
                targetName: targetName,
                minimumAccessLevel: minimumAccessLevel
            )
        }
    }

    // MARK: - Tool Handlers

    private func handleGetProjectSymbols(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let projectPath = args["project_path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: project_path")], isError: true)
        }

        let targetFilter = args["target"]?.stringValue
        let accessLevelStr = args["minimum_access_level"]?.stringValue ?? "public"
        let minimumAccessLevel = AccessLevel(rawValue: accessLevelStr) ?? .public
        let includeDependencies = args["include_dependencies"]?.boolValue ?? false

        // Detect project type and parse
        let project: Project
        if projectPath.hasSuffix(".xcodeproj") || projectPath.hasSuffix(".xcworkspace") ||
           FileManager.default.fileExists(atPath: "\(projectPath)/project.pbxproj") {
            project = try await xcodeParser.parseProject(at: projectPath)
        } else if FileManager.default.fileExists(atPath: "\(projectPath)/Package.swift") ||
                  projectPath.hasSuffix("Package.swift") {
            project = try await spmParser.parsePackage(at: projectPath)
        } else {
            // Try to detect based on directory contents
            let contents = try FileManager.default.contentsOfDirectory(atPath: projectPath)
            if contents.contains("Package.swift") {
                project = try await spmParser.parsePackage(at: projectPath)
            } else if contents.first(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) != nil {
                project = try await xcodeParser.parseProject(at: projectPath)
            } else {
                return .init(content: [.text("Could not detect project type at: \(projectPath)")], isError: true)
            }
        }

        // Filter targets if specified
        let targetsToAnalyze = targetFilter != nil
            ? project.targets.filter { $0.name == targetFilter }
            : project.targets

        if targetsToAnalyze.isEmpty {
            return .init(content: [.text("No targets found matching criteria")], isError: true)
        }

        var allSymbols: [Symbol] = []
        var dependencySymbols: [String: [Symbol]] = [:]

        // Extract project symbols
        for target in targetsToAnalyze {
            do {
                let symbols = try await extractSymbols(
                    from: project,
                    targetName: target.moduleName,
                    minimumAccessLevel: minimumAccessLevel
                )
                allSymbols.append(contentsOf: symbols)
            } catch {
                // Continue with other targets if one fails
                continue
            }
        }

        // Extract dependency symbols if requested
        if includeDependencies && project.type == .spm {
            dependencySymbols = try await dependencyService.extractDependencySymbols(
                at: project.path,
                minimumAccessLevel: minimumAccessLevel
            )
        }

        // Build response
        var response = "# Project Symbols\n\n"
        response += "Found \(allSymbols.count) symbols in \(project.name)\n\n"

        if !allSymbols.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(allSymbols)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            response += "## \(project.name) Symbols\n\n\(jsonString)\n\n"
        }

        if !dependencySymbols.isEmpty {
            let totalDepSymbols = dependencySymbols.values.reduce(0) { $0 + $1.count }
            response += "# Dependency Symbols\n\n"
            response += "Found \(totalDepSymbols) symbols across \(dependencySymbols.count) dependencies\n\n"

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            for (moduleName, symbols) in dependencySymbols.sorted(by: { $0.key < $1.key }) {
                response += "## \(moduleName) (\(symbols.count) symbols)\n\n"
                let jsonData = try encoder.encode(symbols)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
                response += "\(jsonString)\n\n"
            }
        }

        if allSymbols.isEmpty && dependencySymbols.isEmpty {
            return .init(content: [.text("No symbols found. The project may need to be built first, or no public symbols exist.")], isError: false)
        }

        return .init(content: [.text(response)], isError: false)
    }

    private func handleGetProjectDependencies(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let projectPath = args["project_path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: project_path")], isError: true)
        }

        let includeSymbols = args["include_symbols"]?.boolValue ?? false

        // Get dependency information
        let dependencies = try await dependencyService.getDependencies(at: projectPath)

        var response = "# Project Dependencies\n\n"
        response += "**Package:** \(dependencies.packageName)\n\n"

        // List external dependencies
        response += "## External Dependencies\n\n"
        if dependencies.dependencies.isEmpty {
            response += "No external dependencies\n\n"
        } else {
            for dep in dependencies.dependencies {
                response += "### \(dep.name)\n"
                if let url = dep.url {
                    response += "- URL: \(url)\n"
                }
                if let req = dep.requirement {
                    response += "- Requirement: \(req)\n"
                }
                if let resolved = dependencies.resolvedVersions[dep.name.lowercased()] {
                    if let version = resolved.version {
                        response += "- Resolved Version: \(version)\n"
                    } else if let branch = resolved.branch {
                        response += "- Branch: \(branch)\n"
                    }
                    response += "- Revision: \(resolved.revision.prefix(8))\n"
                }
                response += "\n"
            }
        }

        // List targets and their dependencies
        response += "## Targets\n\n"
        for target in dependencies.targets {
            response += "### \(target.name)"
            if target.type != "regular" {
                response += " (\(target.type))"
            }
            response += "\n"

            if target.dependencies.isEmpty {
                response += "- No dependencies\n"
            } else {
                response += "- Dependencies:\n"
                for dep in target.dependencies {
                    var depStr = "  - \(dep.name)"
                    if let pkg = dep.package {
                        depStr += " (from \(pkg))"
                    }
                    depStr += " [\(dep.kind)]"
                    response += "\(depStr)\n"
                }
            }
            response += "\n"
        }

        // Include symbols if requested
        if includeSymbols {
            response += "## Dependency Symbols\n\n"
            response += "Extracting symbols from dependencies (this may take a moment)...\n\n"

            let dependencySymbols = try await dependencyService.extractDependencySymbols(
                at: projectPath,
                minimumAccessLevel: .public
            )

            if dependencySymbols.isEmpty {
                response += "No dependency symbols extracted. Dependencies may need to be built first.\n\n"
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                for (moduleName, symbols) in dependencySymbols.sorted(by: { $0.key < $1.key }) {
                    response += "### \(moduleName) (\(symbols.count) public symbols)\n\n"

                    // Show summary of symbol types
                    let typeCount = symbols.filter { $0.kind == .struct || $0.kind == .class || $0.kind == .enum || $0.kind == .protocol || $0.kind == .actor }.count
                    let funcCount = symbols.filter { $0.kind == .func }.count
                    let propCount = symbols.filter { $0.kind == .var || $0.kind == .let }.count

                    response += "Types: \(typeCount), Functions: \(funcCount), Properties: \(propCount)\n\n"

                    // List the symbols
                    let jsonData = try encoder.encode(symbols)
                    let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
                    response += "\(jsonString)\n\n"
                }
            }
        }

        return .init(content: [.text(response)], isError: false)
    }

    private func handleGetSymbolDocumentation(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let projectPath = args["project_path"]?.stringValue,
              let symbolName = args["symbol_name"]?.stringValue else {
            return .init(content: [.text("Missing required parameters: project_path and symbol_name")], isError: true)
        }

        // Parse project and extract symbols
        let project: Project
        if FileManager.default.fileExists(atPath: "\(projectPath)/Package.swift") ||
           projectPath.hasSuffix("Package.swift") {
            project = try await spmParser.parsePackage(at: projectPath)
        } else {
            project = try await xcodeParser.parseProject(at: projectPath)
        }

        // Search for the symbol
        for target in project.targets {
            let symbols = try await extractSymbols(
                from: project,
                targetName: target.moduleName,
                minimumAccessLevel: .private
            )

            if let symbol = symbols.first(where: {
                $0.fullyQualifiedName == symbolName ||
                $0.name == symbolName ||
                "\(target.moduleName).\($0.name)" == symbolName
            }) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let jsonData = try encoder.encode(symbol)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

                return .init(content: [.text(jsonString)], isError: false)
            }
        }

        return .init(content: [.text("Symbol not found: \(symbolName)")], isError: true)
    }

    private func handleLookupAppleAPI(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let args = arguments ?? [:]

        // Option 1: Direct URL
        if let urlString = args["url"]?.stringValue {
            do {
                let response = try await appleDocsService.fetchFromURL(urlString)
                // Extract framework from URL for conversion
                let pathComponents = urlString
                    .replacingOccurrences(of: "https://developer.apple.com/documentation/", with: "")
                    .components(separatedBy: "/")
                let framework = pathComponents.first ?? "Unknown"

                let documentation = await appleDocsService.convertToDocumentation(response, framework: framework)

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let jsonData = try encoder.encode(documentation)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

                return .init(content: [.text(jsonString)], isError: false)
            } catch {
                return .init(content: [.text("Error: \(error.localizedDescription)")], isError: true)
            }
        }

        // Option 2: Framework + optional symbol
        guard let framework = args["framework"]?.stringValue else {
            return .init(content: [.text("Please provide either 'url' or 'framework' parameter")], isError: true)
        }

        let symbol = args["symbol"]?.stringValue
        let useLocal = args["use_local"]?.boolValue ?? true

        // Try local docs first if requested
        if useLocal {
            if await localDocsService.isAvailable() {
                do {
                    let localSymbols = try await localDocsService.getSwiftInterfaceDocumentation(framework: framework)
                    if let symbolName = symbol {
                        if let found = localSymbols.first(where: { $0.name.lowercased().contains(symbolName.lowercased()) }) {
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            let jsonData = try encoder.encode(found)
                            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                            return .init(content: [.text("From local Xcode documentation:\n\n\(jsonString)")], isError: false)
                        }
                    } else if !localSymbols.isEmpty {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        let jsonData = try encoder.encode(Array(localSymbols.prefix(50)))
                        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
                        return .init(content: [.text("From local Xcode documentation (\(localSymbols.count) symbols, showing first 50):\n\n\(jsonString)")], isError: false)
                    }
                } catch {
                    // Fall back to web docs
                }
            }
        }

        // Fetch from web
        if let symbolPath = symbol {
            do {
                let response = try await appleDocsService.fetchSymbolDocs(framework: framework, symbolPath: symbolPath)
                let documentation = await appleDocsService.convertToDocumentation(response, framework: framework)

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let jsonData = try encoder.encode(documentation)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

                return .init(content: [.text(jsonString)], isError: false)
            } catch {
                return .init(content: [.text("Error looking up '\(symbolPath)' in \(framework): \(error.localizedDescription)\n\nTip: Use symbol names like 'Chart' or 'View', not article URLs.")], isError: true)
            }
        } else {
            do {
                let response = try await appleDocsService.fetchFrameworkDocs(framework: framework)
                let documentation = await appleDocsService.convertToDocumentation(response, framework: framework)

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let jsonData = try encoder.encode(documentation)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

                return .init(content: [.text(jsonString)], isError: false)
            } catch {
                return .init(content: [.text("Error looking up framework '\(framework)': \(error.localizedDescription)\n\nCommon frameworks: SwiftUI, Foundation, UIKit, Charts, Combine, CoreData")], isError: true)
            }
        }
    }

    private func handleSearchSymbols(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let query = args["query"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: query")], isError: true)
        }

        let maxResults = args["max_results"]?.intValue ?? 50
        var resultSets: [[SearchService.ScoredResult]] = []

        // Search in project if specified
        if let projectPath = args["project_path"]?.stringValue {
            let project: Project
            if FileManager.default.fileExists(atPath: "\(projectPath)/Package.swift") ||
               projectPath.hasSuffix("Package.swift") {
                project = try await spmParser.parsePackage(at: projectPath)
            } else {
                project = try await xcodeParser.parseProject(at: projectPath)
            }

            for target in project.targets {
                do {
                    let symbols = try await extractSymbols(
                        from: project,
                        targetName: target.moduleName,
                        minimumAccessLevel: .public
                    )

                    let projectResults = await searchService.search(
                        query: query,
                        symbols: symbols,
                        source: "project:\(project.name)",
                        maxResults: maxResults
                    )
                    resultSets.append(projectResults)
                } catch {
                    continue
                }
            }
        }

        // Search in Apple frameworks
        let frameworksToSearch: [String]
        if let frameworks = args["frameworks"]?.arrayValue {
            frameworksToSearch = frameworks.compactMap { $0.stringValue }
        } else {
            frameworksToSearch = ["Foundation", "SwiftUI", "UIKit", "Combine"]
        }

        for framework in frameworksToSearch {
            do {
                let appleResults = try await appleDocsService.searchSymbol(query: query, in: framework)
                let scoredResults = await searchService.searchAppleDocs(
                    query: query,
                    docs: appleResults,
                    framework: framework,
                    maxResults: 20
                )
                resultSets.append(scoredResults)
            } catch {
                continue
            }
        }

        // Merge and rank all results
        let mergedResults = await searchService.mergeResults(resultSets, maxResults: maxResults)

        if mergedResults.isEmpty {
            return .init(content: [.text("No symbols found matching: \(query)")], isError: false)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(mergedResults)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        // Group results by match type for summary
        let matchTypes = Dictionary(grouping: mergedResults, by: { $0.matchType })
        var summary = "Found \(mergedResults.count) matching symbols"
        let typeCounts = matchTypes.map { "\($0.value.count) \($0.key)" }.joined(separator: ", ")
        summary += " (\(typeCounts)):\n\n"

        return .init(content: [.text(summary + jsonString)], isError: false)
    }

    private func handleGetDependencyDocs(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let args = arguments ?? [:]

        // Option 1: Direct GitHub URL
        if let githubURL = args["github_url"]?.stringValue {
            let docs = try await gitHubDocsService.fetchDocs(from: githubURL)
            return formatGitHubDocs(docs)
        }

        // Option 2: Look up from project dependencies
        guard let projectPath = args["project_path"]?.stringValue,
              let dependencyName = args["dependency_name"]?.stringValue else {
            return .init(content: [.text("Please provide either 'github_url' or both 'project_path' and 'dependency_name'")], isError: true)
        }

        // Get dependencies to find the URL
        let dependencies = try await dependencyService.getDependencies(at: projectPath)

        // Find the dependency
        let searchName = dependencyName.lowercased()
        var foundURL: String?

        // Check in resolved versions
        for (name, resolved) in dependencies.resolvedVersions {
            if name.lowercased().contains(searchName) || searchName.contains(name.lowercased()) {
                foundURL = resolved.repositoryURL
                break
            }
        }

        // Check in dependencies list
        if foundURL == nil {
            for dep in dependencies.dependencies {
                if dep.name.lowercased().contains(searchName) || searchName.contains(dep.name.lowercased()) {
                    foundURL = dep.url
                    break
                }
            }
        }

        guard let url = foundURL else {
            return .init(content: [.text("Dependency '\(dependencyName)' not found in project. Available dependencies: \(dependencies.dependencies.map { $0.name }.joined(separator: ", "))")], isError: true)
        }

        let docs = try await gitHubDocsService.fetchDocs(from: url)
        return formatGitHubDocs(docs)
    }

    private func formatGitHubDocs(_ docs: GitHubDocsService.GitHubDocs) -> CallTool.Result {
        var response = "# \(docs.repositoryName)\n\n"

        if let description = docs.description {
            response += "**Description:** \(description)\n\n"
        }

        response += "**URL:** \(docs.repositoryURL)\n"

        if let stars = docs.stars {
            response += "**Stars:** \(stars)\n"
        }

        if let license = docs.license {
            response += "**License:** \(license)\n"
        }

        if !docs.topics.isEmpty {
            response += "**Topics:** \(docs.topics.joined(separator: ", "))\n"
        }

        response += "\n---\n\n"

        if let readme = docs.readme {
            response += "## README\n\n\(readme)\n\n"
        }

        for docFile in docs.documentationFiles {
            response += "---\n\n## \(docFile.name)\n\n\(docFile.content)\n\n"
        }

        return .init(content: [.text(response)], isError: false)
    }

    private func handleGetProjectSummary(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let projectPath = args["project_path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: project_path")], isError: true)
        }

        var response = "# Project Summary\n\n"

        // Detect project type and parse
        let project: Project
        let isSPM: Bool
        if projectPath.hasSuffix(".xcodeproj") || projectPath.hasSuffix(".xcworkspace") ||
           FileManager.default.fileExists(atPath: "\(projectPath)/project.pbxproj") {
            project = try await xcodeParser.parseProject(at: projectPath)
            isSPM = false
        } else if FileManager.default.fileExists(atPath: "\(projectPath)/Package.swift") ||
                  projectPath.hasSuffix("Package.swift") {
            project = try await spmParser.parsePackage(at: projectPath)
            isSPM = true
        } else {
            let contents = try FileManager.default.contentsOfDirectory(atPath: projectPath)
            if contents.contains("Package.swift") {
                project = try await spmParser.parsePackage(at: projectPath)
                isSPM = true
            } else if contents.first(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) != nil {
                project = try await xcodeParser.parseProject(at: projectPath)
                isSPM = false
            } else {
                return .init(content: [.text("Could not detect project type at: \(projectPath)")], isError: true)
            }
        }

        response += "**Name:** \(project.name)\n"
        response += "**Type:** \(project.type.rawValue)\n"
        response += "**Path:** \(project.path)\n\n"

        // Targets
        response += "## Targets (\(project.targets.count))\n\n"
        for target in project.targets {
            response += "### \(target.name)\n"
            response += "- Module: `\(target.moduleName)`\n"
            if !target.dependencies.isEmpty {
                response += "- Dependencies: \(target.dependencies.joined(separator: ", "))\n"
            }
            response += "\n"
        }

        // Dependencies (for SPM projects)
        if isSPM {
            let dependencies = try await dependencyService.getDependencies(at: project.path)

            if !dependencies.dependencies.isEmpty {
                response += "## External Dependencies (\(dependencies.dependencies.count))\n\n"
                for dep in dependencies.dependencies {
                    response += "- **\(dep.name)**"
                    if let resolved = dependencies.resolvedVersions[dep.name.lowercased()],
                       let version = resolved.version {
                        response += " (v\(version))"
                    }
                    response += "\n"
                }
                response += "\n"
            }
        }

        // Key symbols summary
        response += "## Key Types\n\n"
        var allSymbols: [Symbol] = []

        for target in project.targets {
            do {
                let symbols = try await extractSymbols(
                    from: project,
                    targetName: target.moduleName,
                    minimumAccessLevel: .public
                )
                allSymbols.append(contentsOf: symbols)
            } catch {
                continue
            }
        }

        if allSymbols.isEmpty {
            let buildHint = project.type == .spm
                ? "Run `swift build` first."
                : "Build the project in Xcode first."
            response += "_No public symbols found. \(buildHint)_\n\n"
        } else {
            // Group by kind
            let structs = allSymbols.filter { $0.kind == .struct }
            let classes = allSymbols.filter { $0.kind == .class }
            let protocols = allSymbols.filter { $0.kind == .protocol }
            let enums = allSymbols.filter { $0.kind == .enum }
            let actors = allSymbols.filter { $0.kind == .actor }
            let functions = allSymbols.filter { $0.kind == .func }

            response += "| Category | Count | Examples |\n"
            response += "|----------|-------|----------|\n"

            if !structs.isEmpty {
                let examples = structs.prefix(3).map { $0.name }.joined(separator: ", ")
                response += "| Structs | \(structs.count) | \(examples) |\n"
            }
            if !classes.isEmpty {
                let examples = classes.prefix(3).map { $0.name }.joined(separator: ", ")
                response += "| Classes | \(classes.count) | \(examples) |\n"
            }
            if !protocols.isEmpty {
                let examples = protocols.prefix(3).map { $0.name }.joined(separator: ", ")
                response += "| Protocols | \(protocols.count) | \(examples) |\n"
            }
            if !enums.isEmpty {
                let examples = enums.prefix(3).map { $0.name }.joined(separator: ", ")
                response += "| Enums | \(enums.count) | \(examples) |\n"
            }
            if !actors.isEmpty {
                let examples = actors.prefix(3).map { $0.name }.joined(separator: ", ")
                response += "| Actors | \(actors.count) | \(examples) |\n"
            }
            if !functions.isEmpty {
                let examples = functions.prefix(3).map { $0.name }.joined(separator: ", ")
                response += "| Functions | \(functions.count) | \(examples) |\n"
            }

            response += "\n**Total public symbols:** \(allSymbols.count)\n"
        }

        return .init(content: [.text(response)], isError: false)
    }

    // MARK: - Build, Test, Run Handlers

    private func handleSwiftBuild(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let projectPath = args["project_path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: project_path")], isError: true)
        }

        let configuration = args["configuration"]?.stringValue ?? "debug"
        let target = args["target"]?.stringValue
        let clean = args["clean"]?.boolValue ?? false

        let result = try await buildService.swiftBuild(
            at: projectPath,
            configuration: configuration,
            target: target,
            clean: clean
        )

        return formatBuildResult(result)
    }

    private func handleSwiftTest(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let projectPath = args["project_path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: project_path")], isError: true)
        }

        let filter = args["filter"]?.stringValue
        let parallel = args["parallel"]?.boolValue ?? true
        let enableCodeCoverage = args["enable_code_coverage"]?.boolValue ?? false

        let result = try await buildService.swiftTest(
            at: projectPath,
            filter: filter,
            parallel: parallel,
            enableCodeCoverage: enableCodeCoverage
        )

        return formatTestResult(result)
    }

    private func handleSwiftRun(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let projectPath = args["project_path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: project_path")], isError: true)
        }

        let executable = args["executable"]?.stringValue
        let execArguments = args["arguments"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        let configuration = args["configuration"]?.stringValue ?? "debug"
        let timeout = TimeInterval(args["timeout"]?.intValue ?? 60)

        let result = try await buildService.swiftRun(
            at: projectPath,
            executable: executable,
            arguments: execArguments,
            configuration: configuration,
            timeout: timeout
        )

        return formatRunResult(result)
    }

    private func handleXcodebuildBuild(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let projectPath = args["project_path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: project_path")], isError: true)
        }

        let scheme = args["scheme"]?.stringValue
        let configuration = args["configuration"]?.stringValue ?? "Debug"
        let destination = args["destination"]?.stringValue
        let destinationPlatform = args["destination_platform"]?.stringValue
        let clean = args["clean"]?.boolValue ?? false

        let result = try await buildService.xcodebuild(
            at: projectPath,
            scheme: scheme,
            configuration: configuration,
            destination: destination,
            destinationPlatform: destinationPlatform,
            clean: clean
        )

        return formatBuildResult(result)
    }

    private func handleXcodebuildTest(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let projectPath = args["project_path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: project_path")], isError: true)
        }

        let scheme = args["scheme"]?.stringValue
        let destination = args["destination"]?.stringValue
        let destinationPlatform = args["destination_platform"]?.stringValue
        let testPlan = args["test_plan"]?.stringValue
        let onlyTesting = args["only_testing"]?.arrayValue?.compactMap { $0.stringValue }
        let skipTesting = args["skip_testing"]?.arrayValue?.compactMap { $0.stringValue }
        let enableCodeCoverage = args["enable_code_coverage"]?.boolValue ?? false

        let result = try await buildService.xcodeTest(
            at: projectPath,
            scheme: scheme,
            destination: destination,
            destinationPlatform: destinationPlatform,
            testPlan: testPlan,
            onlyTesting: onlyTesting,
            skipTesting: skipTesting,
            enableCodeCoverage: enableCodeCoverage
        )

        return formatTestResult(result)
    }

    private func handleListSchemes(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let projectPath = args["project_path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: project_path")], isError: true)
        }

        let schemes = try await buildService.listSchemes(at: projectPath)

        let result = SchemesResult(projectPath: projectPath, schemes: schemes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(jsonString)], isError: false)
    }

    private func handleListDestinations(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let projectPath = args["project_path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: project_path")], isError: true)
        }

        let scheme = args["scheme"]?.stringValue
        let platform = args["platform"]?.stringValue

        let destinations = try await buildService.listDestinations(
            at: projectPath,
            scheme: scheme,
            platform: platform
        )

        let result = DestinationsResult(
            projectPath: projectPath,
            scheme: scheme,
            destinations: destinations
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(jsonString)], isError: false)
    }

    private func handleInstrumentsProfile(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let target = args["target"]?.stringValue,
              let template = args["template"]?.stringValue else {
            return .init(content: [.text("Missing required parameters: target and template")], isError: true)
        }

        let duration = args["duration"]?.intValue ?? 10
        let outputPath = args["output_path"]?.stringValue
        let device = args["device"]?.stringValue

        let result = try await instrumentsService.profile(
            target: target,
            template: template,
            duration: duration,
            outputPath: outputPath,
            device: device
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        var response = "## Profiling Complete\n\n"
        response += result.summaryText + "\n\n"
        response += "Trace file: `\(result.tracePath)`\n\n"
        response += "### Details\n\n\(jsonString)"

        return .init(content: [.text(response)], isError: false)
    }

    private func handleListInstrumentsTemplates(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let templates = try await instrumentsService.listTemplates()

        let result = TemplatesResult(templates: templates)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(jsonString)], isError: false)
    }

    // MARK: - Result Formatting Helpers

    private func formatBuildResult(_ result: BuildResult) -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let jsonData = try encoder.encode(result)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            var response = "## Build Result\n\n"
            response += result.summary + "\n\n"

            if !result.errors.isEmpty {
                response += "### Errors (\(result.errors.count))\n\n"
                for error in result.errors {
                    if let file = error.file, let line = error.line {
                        response += "- `\(file):\(line)`: \(error.message)\n"
                    } else {
                        response += "- \(error.message)\n"
                    }
                }
                response += "\n"
            }

            if !result.warnings.isEmpty {
                response += "### Warnings (\(result.warnings.count))\n\n"
                for warning in result.warnings.prefix(10) {
                    if let file = warning.file, let line = warning.line {
                        response += "- `\(file):\(line)`: \(warning.message)\n"
                    } else {
                        response += "- \(warning.message)\n"
                    }
                }
                if result.warnings.count > 10 {
                    response += "- ... and \(result.warnings.count - 10) more\n"
                }
                response += "\n"
            }

            response += "### Full Result\n\n```json\n\(jsonString)\n```"

            return .init(content: [.text(response)], isError: !result.success)
        } catch {
            return .init(content: [.text("Error encoding result: \(error)")], isError: true)
        }
    }

    private func formatTestResult(_ result: TestResult) -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let jsonData = try encoder.encode(result)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            var response = "## Test Result\n\n"
            response += result.summary + "\n\n"

            response += "| Status | Count |\n"
            response += "|--------|-------|\n"
            response += "| Passed | \(result.passed) |\n"
            response += "| Failed | \(result.failed) |\n"
            response += "| Skipped | \(result.skipped) |\n"
            response += "| **Total** | **\(result.totalTests)** |\n\n"

            // Show failed tests
            let failedTests = result.testCases.filter { $0.status == .failed }
            if !failedTests.isEmpty {
                response += "### Failed Tests\n\n"
                for test in failedTests {
                    response += "#### \(test.className).\(test.name)\n"
                    if let message = test.failureMessage {
                        response += "- **Error**: \(message)\n"
                    }
                    if let location = test.failureLocation {
                        response += "- **Location**: `\(location)`\n"
                    }
                    response += "\n"
                }
            }

            response += "### Full Result\n\n```json\n\(jsonString)\n```"

            return .init(content: [.text(response)], isError: !result.success)
        } catch {
            return .init(content: [.text("Error encoding result: \(error)")], isError: true)
        }
    }

    private func formatRunResult(_ result: RunResult) -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let jsonData = try encoder.encode(result)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            var response = "## Run Result\n\n"
            response += result.summary + "\n\n"

            if !result.stdout.isEmpty {
                response += "### Standard Output\n\n```\n\(result.stdout.prefix(5000))"
                if result.stdout.count > 5000 {
                    response += "\n... (truncated, \(result.stdout.count) total characters)"
                }
                response += "\n```\n\n"
            }

            if !result.stderr.isEmpty {
                response += "### Standard Error\n\n```\n\(result.stderr.prefix(2000))"
                if result.stderr.count > 2000 {
                    response += "\n... (truncated)"
                }
                response += "\n```\n\n"
            }

            response += "### Details\n\n```json\n\(jsonString)\n```"

            return .init(content: [.text(response)], isError: !result.success)
        } catch {
            return .init(content: [.text("Error encoding result: \(error)")], isError: true)
        }
    }

    // MARK: - Simulator Handlers (simctl)

    private func handleSimctlListDevices(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let args = arguments ?? [:]

        let platform: SimulatorPlatform? = args["platform"]?.stringValue.flatMap { SimulatorPlatform(rawValue: $0) }
        let state: DeviceState? = args["state"]?.stringValue.flatMap { DeviceState(rawValue: $0) }
        let availableOnly = args["available_only"]?.boolValue ?? true

        let result = try await simulatorService.listDevices(
            platform: platform,
            state: state,
            availableOnly: availableOnly
        )

        var response = "## Simulator Devices\n\n"
        response += result.summary + "\n\n"

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        response += "```json\n\(jsonString)\n```"

        return .init(content: [.text(response)], isError: false)
    }

    private func handleSimctlListRuntimes(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let args = arguments ?? [:]
        let platform: SimulatorPlatform? = args["platform"]?.stringValue.flatMap { SimulatorPlatform(rawValue: $0) }

        var runtimes = try await simulatorService.listRuntimes()

        // Filter by platform if specified
        if let platform = platform {
            runtimes = runtimes.filter { $0.platform == platform }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(runtimes)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        var response = "## Available Runtimes\n\n"
        response += "Found \(runtimes.count) runtimes\n\n"
        response += "```json\n\(jsonString)\n```"

        return .init(content: [.text(response)], isError: false)
    }

    private func handleSimctlDeviceControl(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: action")], isError: true)
        }

        let result: SimulatorOperationResult

        switch action {
        case "boot":
            guard let deviceId = args["device_id"]?.stringValue else {
                return .init(content: [.text("Missing required parameter: device_id")], isError: true)
            }
            result = try await simulatorService.bootDevice(deviceId)

        case "shutdown":
            guard let deviceId = args["device_id"]?.stringValue else {
                return .init(content: [.text("Missing required parameter: device_id")], isError: true)
            }
            result = try await simulatorService.shutdownDevice(deviceId)

        case "create":
            guard let name = args["device_name"]?.stringValue,
                  let deviceType = args["device_type"]?.stringValue else {
                return .init(content: [.text("Missing required parameters: device_name, device_type")], isError: true)
            }
            let runtime = args["runtime"]?.stringValue
            let device = try await simulatorService.createDevice(name: name, deviceTypeId: deviceType, runtimeId: runtime)
            result = .success("Device created: \(device.name) (\(device.udid))", deviceId: device.udid)

        case "delete":
            guard let deviceId = args["device_id"]?.stringValue else {
                return .init(content: [.text("Missing required parameter: device_id")], isError: true)
            }
            result = try await simulatorService.deleteDevice(deviceId)

        case "erase":
            guard let deviceId = args["device_id"]?.stringValue else {
                return .init(content: [.text("Missing required parameter: device_id")], isError: true)
            }
            result = try await simulatorService.eraseDevice(deviceId)

        case "clone":
            guard let deviceId = args["device_id"]?.stringValue else {
                return .init(content: [.text("Missing required parameter: device_id")], isError: true)
            }
            let newName = args["device_name"]?.stringValue ?? "Cloned Device"
            let device = try await simulatorService.cloneDevice(deviceId, name: newName)
            result = .success("Device cloned: \(device.name) (\(device.udid))", deviceId: device.udid)

        default:
            return .init(content: [.text("Unknown action: \(action)")], isError: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(jsonString)], isError: !result.success)
    }

    private func handleSimctlAppInstall(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let deviceId = args["device_id"]?.stringValue,
              let appPath = args["app_path"]?.stringValue else {
            return .init(content: [.text("Missing required parameters: device_id, app_path")], isError: true)
        }

        let result = try await simulatorService.installApp(deviceId: deviceId, appPath: appPath)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(jsonString)], isError: !result.success)
    }

    private func handleSimctlAppControl(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue,
              let deviceId = args["device_id"]?.stringValue,
              let bundleId = args["bundle_id"]?.stringValue else {
            return .init(content: [.text("Missing required parameters: action, device_id, bundle_id")], isError: true)
        }

        switch action {
        case "launch":
            let launchArgs = args["arguments"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            let waitForDebugger = args["wait_for_debugger"]?.boolValue ?? false
            let result = try await simulatorService.launchApp(
                deviceId: deviceId,
                bundleId: bundleId,
                arguments: launchArgs,
                waitForDebugger: waitForDebugger
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(result)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            return .init(content: [.text(jsonString)], isError: !result.success)

        case "terminate":
            let result = try await simulatorService.terminateApp(deviceId: deviceId, bundleId: bundleId)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(result)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            return .init(content: [.text(jsonString)], isError: !result.success)

        case "uninstall":
            let result = try await simulatorService.uninstallApp(deviceId: deviceId, bundleId: bundleId)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(result)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            return .init(content: [.text(jsonString)], isError: !result.success)

        default:
            return .init(content: [.text("Unknown action: \(action)")], isError: true)
        }
    }

    private func handleSimctlAppInfo(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let deviceId = args["device_id"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: device_id")], isError: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let bundleId = args["bundle_id"]?.stringValue {
            let info = try await simulatorService.getAppInfo(deviceId: deviceId, bundleId: bundleId)
            let jsonData = try encoder.encode(info)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            return .init(content: [.text(jsonString)], isError: false)
        } else {
            let apps = try await simulatorService.listApps(deviceId: deviceId)
            let jsonData = try encoder.encode(apps)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

            var response = "## Installed Apps\n\n"
            response += "Found \(apps.count) apps\n\n"
            response += "```json\n\(jsonString)\n```"

            return .init(content: [.text(response)], isError: false)
        }
    }

    private func handleSimctlScreenshot(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let deviceId = args["device_id"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: device_id")], isError: true)
        }

        let outputPath = args["output_path"]?.stringValue
        let format: ScreenshotFormat = args["format"]?.stringValue.flatMap { ScreenshotFormat(rawValue: $0) } ?? .png
        let mask: MaskPolicy = args["mask"]?.stringValue.flatMap { MaskPolicy(rawValue: $0) } ?? .ignored

        let result = try await simulatorService.takeScreenshot(
            deviceId: deviceId,
            outputPath: outputPath,
            format: format,
            mask: mask
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        var response = "## Screenshot Captured\n\n"
        response += result.summary + "\n\n"
        response += "```json\n\(jsonString)\n```"

        return .init(content: [.text(response)], isError: false)
    }

    private func handleSimctlRecordVideo(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue,
              let deviceId = args["device_id"]?.stringValue else {
            return .init(content: [.text("Missing required parameters: action, device_id")], isError: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        switch action {
        case "start":
            let outputPath = args["output_path"]?.stringValue
            let codec: VideoCodec = args["codec"]?.stringValue.flatMap { VideoCodec(rawValue: $0) } ?? .h264

            let handle = try await simulatorService.startRecording(
                deviceId: deviceId,
                outputPath: outputPath,
                codec: codec
            )

            // Store the handle for later retrieval
            await recordingManager.store(handle)

            let jsonData = try encoder.encode(handle)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            var response = "## Recording Started\n\n"
            response += "Recording ID: `\(handle.id)`\n"
            response += "Output: `\(handle.outputPath)`\n\n"
            response += "Use `simctl_record_video` with action=stop and recording_id=`\(handle.id)` to stop.\n\n"
            response += "```json\n\(jsonString)\n```"

            return .init(content: [.text(response)], isError: false)

        case "stop":
            guard let recordingId = args["recording_id"]?.stringValue else {
                return .init(content: [.text("Missing required parameter: recording_id")], isError: true)
            }

            // Retrieve the handle
            guard let handle = await recordingManager.retrieve(recordingId) else {
                return .init(content: [.text("Recording not found: \(recordingId)")], isError: true)
            }

            let result = try await simulatorService.stopRecording(handle)

            let jsonData = try encoder.encode(result)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            var response = "## Recording Stopped\n\n"
            response += result.summary + "\n\n"
            response += "```json\n\(jsonString)\n```"

            return .init(content: [.text(response)], isError: false)

        default:
            return .init(content: [.text("Unknown action: \(action). Use 'start' or 'stop'.")], isError: true)
        }
    }

    private func handleSimctlLocation(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue,
              let deviceId = args["device_id"]?.stringValue else {
            return .init(content: [.text("Missing required parameters: action, device_id")], isError: true)
        }

        let result: SimulatorOperationResult

        switch action {
        case "set":
            guard let lat = args["latitude"]?.doubleValue,
                  let lon = args["longitude"]?.doubleValue else {
                return .init(content: [.text("Missing required parameters: latitude, longitude")], isError: true)
            }
            result = try await simulatorService.setLocation(deviceId: deviceId, latitude: lat, longitude: lon)

        case "clear":
            result = try await simulatorService.clearLocation(deviceId: deviceId)

        default:
            return .init(content: [.text("Unknown action: \(action). Use 'set' or 'clear'.")], isError: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(jsonString)], isError: !result.success)
    }

    private func handleSimctlPush(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let deviceId = args["device_id"]?.stringValue,
              let bundleId = args["bundle_id"]?.stringValue else {
            return .init(content: [.text("Missing required parameters: device_id, bundle_id")], isError: true)
        }

        let payload = PushPayload(
            title: args["title"]?.stringValue,
            body: args["body"]?.stringValue,
            subtitle: args["subtitle"]?.stringValue,
            badge: args["badge"]?.intValue
        )

        let result = try await simulatorService.sendPushNotification(
            deviceId: deviceId,
            bundleId: bundleId,
            payload: payload
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(jsonString)], isError: !result.success)
    }

    private func handleSimctlPrivacy(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue,
              let deviceId = args["device_id"]?.stringValue,
              let bundleId = args["bundle_id"]?.stringValue,
              let serviceStr = args["service"]?.stringValue else {
            return .init(content: [.text("Missing required parameters: action, device_id, bundle_id, service")], isError: true)
        }

        guard let service = PrivacyService(rawValue: serviceStr) else {
            let validServices = PrivacyService.allCases.map { $0.rawValue }.joined(separator: ", ")
            return .init(content: [.text("Invalid service: \(serviceStr). Valid services: \(validServices)")], isError: true)
        }

        let result: SimulatorOperationResult

        switch action {
        case "grant":
            result = try await simulatorService.grantPermission(deviceId: deviceId, bundleId: bundleId, service: service)
        case "revoke":
            result = try await simulatorService.revokePermission(deviceId: deviceId, bundleId: bundleId, service: service)
        case "reset":
            result = try await simulatorService.resetPermissions(deviceId: deviceId, service: service, bundleId: bundleId)
        default:
            return .init(content: [.text("Unknown action: \(action). Use 'grant', 'revoke', or 'reset'.")], isError: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(jsonString)], isError: !result.success)
    }

    private func handleSimctlStatusBar(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue,
              let deviceId = args["device_id"]?.stringValue else {
            return .init(content: [.text("Missing required parameters: action, device_id")], isError: true)
        }

        let result: SimulatorOperationResult

        switch action {
        case "override":
            var overrides = StatusBarOverrides()
            overrides.time = args["time"]?.stringValue
            overrides.batteryLevel = args["battery_level"]?.intValue
            overrides.batteryState = args["battery_state"]?.stringValue
            overrides.wifiBars = args["wifi_bars"]?.intValue
            overrides.cellularBars = args["cellular_bars"]?.intValue
            overrides.operatorName = args["operator_name"]?.stringValue

            result = try await simulatorService.setStatusBar(deviceId: deviceId, overrides: overrides)

        case "clear":
            result = try await simulatorService.clearStatusBar(deviceId: deviceId)

        default:
            return .init(content: [.text("Unknown action: \(action). Use 'override' or 'clear'.")], isError: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(jsonString)], isError: !result.success)
    }

    private func handleSimctlPasteboard(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue,
              let deviceId = args["device_id"]?.stringValue else {
            return .init(content: [.text("Missing required parameters: action, device_id")], isError: true)
        }

        switch action {
        case "get":
            let content = try await simulatorService.getPasteboard(deviceId: deviceId)
            return .init(content: [.text("**Pasteboard Content:**\n\n```\n\(content)\n```")], isError: false)

        case "set":
            guard let content = args["content"]?.stringValue else {
                return .init(content: [.text("Missing required parameter: content")], isError: true)
            }
            let result = try await simulatorService.setPasteboard(deviceId: deviceId, content: content)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(result)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            return .init(content: [.text(jsonString)], isError: !result.success)

        default:
            return .init(content: [.text("Unknown action: \(action). Use 'get' or 'set'.")], isError: true)
        }
    }

    private func handleSimctlOpenURL(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let deviceId = args["device_id"]?.stringValue,
              let url = args["url"]?.stringValue else {
            return .init(content: [.text("Missing required parameters: device_id, url")], isError: true)
        }

        let result = try await simulatorService.openURL(deviceId: deviceId, url: url)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(jsonString)], isError: !result.success)
    }

    // MARK: - Simulator UI Handlers (Consolidated)

    private func handleSimulatorUIState(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        // Check accessibility permission first
        if !simulatorUIService.checkAccessibility() {
            simulatorUIService.requestAccessibility()
            return .init(content: [.text("""
                ## Accessibility Permission Required

                To interact with the simulator UI, you need to grant Accessibility permission to your terminal app.

                **Steps:**
                1. Open System Settings > Privacy & Security > Accessibility
                2. Enable your terminal app (Terminal, iTerm2, etc.)
                3. Try again after granting permission

                The system prompt should appear automatically.
                """)], isError: true)
        }

        let deviceId = arguments?["device_id"]?.stringValue ?? "booted"

        // Take a screenshot first
        let screenshotResult = try await simulatorService.takeScreenshot(deviceId: deviceId, format: .png, mask: .ignored)
        let screenshotPath = screenshotResult.path

        // Get UI state with OCR
        let uiState = try await simulatorUIService.getUIState(screenshotPath: screenshotPath)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(uiState)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(uiState.summary + "\n\n```json\n\(jsonString)\n```")], isError: false)
    }

    private func handleSimulatorInteract(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: action")], isError: true)
        }

        let deviceName = args["device_name"]?.stringValue
        let result: UIInteractionResult

        switch action {
        case "tap":
            guard let x = args["x"]?.intValue, let y = args["y"]?.intValue else {
                return .init(content: [.text("tap action requires x and y coordinates")], isError: true)
            }
            result = try await simulatorUIService.tap(x: x, y: y, deviceName: deviceName)

        case "double_tap":
            guard let x = args["x"]?.intValue, let y = args["y"]?.intValue else {
                return .init(content: [.text("double_tap action requires x and y coordinates")], isError: true)
            }
            result = try await simulatorUIService.doubleTap(x: x, y: y, deviceName: deviceName)

        case "long_press":
            guard let x = args["x"]?.intValue, let y = args["y"]?.intValue else {
                return .init(content: [.text("long_press action requires x and y coordinates")], isError: true)
            }
            let duration = args["duration"]?.doubleValue ?? 1.0
            result = try await simulatorUIService.longPress(x: x, y: y, duration: duration, deviceName: deviceName)

        case "swipe":
            guard let x = args["x"]?.intValue,
                  let y = args["y"]?.intValue,
                  let toX = args["to_x"]?.intValue,
                  let toY = args["to_y"]?.intValue else {
                return .init(content: [.text("swipe action requires x, y, to_x, and to_y coordinates")], isError: true)
            }
            let duration = args["duration"]?.doubleValue ?? 0.3
            result = try await simulatorUIService.swipe(fromX: x, fromY: y, toX: toX, toY: toY, duration: duration, deviceName: deviceName)

        case "type":
            guard let text = args["text"]?.stringValue else {
                return .init(content: [.text("type action requires text parameter")], isError: true)
            }
            result = try await simulatorUIService.typeText(text, deviceName: deviceName)

        case "button":
            guard let buttonStr = args["button"]?.stringValue else {
                return .init(content: [.text("button action requires button parameter")], isError: true)
            }
            guard let button = HardwareButton(rawValue: buttonStr) else {
                return .init(content: [.text("Unknown button: \(buttonStr). Valid: home, lock, volumeUp, volumeDown, ringer, screenshot, keyboard")], isError: true)
            }
            result = try await simulatorUIService.pressButton(button, deviceName: deviceName)

        default:
            return .init(content: [.text("Unknown action: \(action). Valid: tap, double_tap, long_press, swipe, type, button")], isError: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(result.summary + "\n\n```json\n\(jsonString)\n```")], isError: !result.success)
    }

    private func handleSimulatorFindText(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let searchText = args["text"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: text")], isError: true)
        }

        let deviceId = args["device_id"]?.stringValue ?? "booted"
        let caseSensitive = args["case_sensitive"]?.boolValue ?? false

        // Take a screenshot first
        let screenshotResult = try await simulatorService.takeScreenshot(deviceId: deviceId, format: .png, mask: .ignored)
        let screenshotPath = screenshotResult.path

        // Find the text
        if let found = try await simulatorUIService.findText(searchText, in: screenshotPath, caseSensitive: caseSensitive) {
            let response: [String: Any] = [
                "found": true,
                "text": found.text,
                "x": found.centerX,
                "y": found.centerY,
                "width": found.width,
                "height": found.height,
                "confidence": found.confidence
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            return .init(content: [.text("""
                ## Text Found: "\(found.text)"

                **Location:** (\(found.centerX), \(found.centerY)) - center point for tapping
                **Size:** \(found.width) × \(found.height) pixels
                **Confidence:** \(String(format: "%.1f%%", found.confidence * 100))

                **To tap this element:**
                ```
                simulator_interact(action: "tap", x: \(found.centerX), y: \(found.centerY))
                ```

                ```json
                \(jsonString)
                ```
                """)], isError: false)
        } else {
            // Text not found - return all visible text to help the agent
            let allText = try await simulatorUIService.recognizeText(in: screenshotPath)
            let visibleTexts = allText.prefix(15).map { "\"\($0.text)\"" }.joined(separator: ", ")

            return .init(content: [.text("""
                ## Text Not Found: "\(searchText)"

                The text was not found on screen.

                **Visible text on screen:**
                \(visibleTexts.isEmpty ? "No text detected" : visibleTexts)
                \(allText.count > 15 ? "\n... and \(allText.count - 15) more" : "")

                **Suggestions:**
                - Check spelling and case (case_sensitive: \(caseSensitive))
                - The text may be partially visible or obscured
                - Try scrolling to reveal more content
                - Use simulator_ui_state to see all text with coordinates
                """)], isError: true)
        }
    }
}

// MARK: - Recording Manager Actor

/// Actor to safely manage recording handles across async contexts
private actor RecordingManager {
    private var handles: [String: RecordingHandle] = [:]

    func store(_ handle: RecordingHandle) {
        handles[handle.id] = handle
    }

    func retrieve(_ id: String) -> RecordingHandle? {
        handles.removeValue(forKey: id)
    }
}
