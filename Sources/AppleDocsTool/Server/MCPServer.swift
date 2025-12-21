import Foundation
import MCP

/// MCP Server for Apple Documentation and Swift project symbols
final class AppleDocsToolServer: @unchecked Sendable {
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

    init() {
        self.server = Server(
            name: "apple-docs-tool",
            version: "1.0.0",
            capabilities: .init(
                tools: .init(listChanged: true)
            )
        )
    }

    func start() async throws {
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
}
