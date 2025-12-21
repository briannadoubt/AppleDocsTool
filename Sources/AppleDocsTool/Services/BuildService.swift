import Foundation

/// Service for building, testing, and running Swift packages and Xcode projects
actor BuildService {
    private let fileManager = FileManager.default

    // MARK: - Error Types

    enum BuildError: Error, LocalizedError {
        case projectNotFound(String)
        case buildFailed(String)
        case testFailed(String)
        case runFailed(String)
        case schemeNotFound(String)
        case invalidProject(String)
        case timeout(Int)

        var errorDescription: String? {
            switch self {
            case .projectNotFound(let path):
                return "Project not found at: \(path)"
            case .buildFailed(let message):
                return "Build failed: \(message)"
            case .testFailed(let message):
                return "Tests failed: \(message)"
            case .runFailed(let message):
                return "Run failed: \(message)"
            case .schemeNotFound(let name):
                return "Scheme not found: \(name)"
            case .invalidProject(let message):
                return "Invalid project: \(message)"
            case .timeout(let seconds):
                return "Operation timed out after \(seconds) seconds"
            }
        }
    }

    // MARK: - Swift Package Operations

    /// Build a Swift package
    func swiftBuild(
        at projectPath: String,
        configuration: String = "debug",
        target: String? = nil,
        clean: Bool = false
    ) async throws -> BuildResult {
        let packageDir = try resolvePackageDirectory(projectPath)

        // Clean if requested
        if clean {
            _ = try? await ProcessRunner.swift(
                arguments: ["package", "clean"],
                workingDirectory: packageDir
            )
        }

        // Build arguments
        var args = ["build", "--configuration", configuration]
        if let target = target {
            args += ["--target", target]
        }

        let result = try await ProcessRunner.swift(
            arguments: args,
            workingDirectory: packageDir,
            timeout: 600  // 10 minutes for builds
        )

        let combinedOutput = result.stdout + "\n" + result.stderr
        let (errors, warnings) = OutputParser.parseBuildOutput(combinedOutput)
        let success = result.exitCode == 0 && errors.isEmpty

        return BuildResult(
            success: success,
            duration: result.duration,
            errors: errors,
            warnings: warnings,
            buildLogPath: nil
        )
    }

    /// Run Swift package tests
    func swiftTest(
        at projectPath: String,
        filter: String? = nil,
        parallel: Bool = true,
        enableCodeCoverage: Bool = false
    ) async throws -> TestResult {
        let packageDir = try resolvePackageDirectory(projectPath)

        var args = ["test"]

        if let filter = filter {
            args += ["--filter", filter]
        }

        if !parallel {
            args += ["--parallel=false"]
        }

        if enableCodeCoverage {
            args += ["--enable-code-coverage"]
        }

        let result = try await ProcessRunner.swift(
            arguments: args,
            workingDirectory: packageDir,
            timeout: 600  // 10 minutes for tests
        )

        let combinedOutput = result.stdout + "\n" + result.stderr
        let testResult = OutputParser.parseTestOutput(combinedOutput)

        // If no test cases were parsed but we have output, create a basic result
        if testResult.testCases.isEmpty && result.exitCode != 0 {
            let (errors, _) = OutputParser.parseBuildOutput(combinedOutput)
            if !errors.isEmpty {
                // Build failed before tests could run
                return TestResult(
                    success: false,
                    duration: result.duration,
                    totalTests: 0,
                    passed: 0,
                    failed: 0,
                    skipped: 0,
                    testCases: [],
                    codeCoverage: nil
                )
            }
        }

        return testResult
    }

    /// Run a Swift package executable
    func swiftRun(
        at projectPath: String,
        executable: String? = nil,
        arguments: [String] = [],
        configuration: String = "debug",
        timeout: TimeInterval = 60
    ) async throws -> RunResult {
        let packageDir = try resolvePackageDirectory(projectPath)

        var args = ["run"]

        if let executable = executable {
            args += [executable]
        }

        args += ["--configuration", configuration]

        // Add executable arguments after --
        if !arguments.isEmpty {
            args += ["--"]
            args += arguments
        }

        let result = try await ProcessRunner.swift(
            arguments: args,
            workingDirectory: packageDir,
            timeout: timeout
        )

        return RunResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            duration: result.duration,
            wasTerminated: result.wasTerminated
        )
    }

    // MARK: - Xcode Build Operations

    /// Build an Xcode project or workspace
    func xcodebuild(
        at projectPath: String,
        scheme: String? = nil,
        configuration: String = "Debug",
        destination: String? = nil,
        destinationPlatform: String? = nil,
        clean: Bool = false
    ) async throws -> BuildResult {
        let (projectArg, projectValue) = try await resolveXcodeProject(projectPath)

        var args = [projectArg, projectValue]

        // Get or detect scheme
        let schemeName: String
        if let scheme = scheme {
            schemeName = scheme
        } else {
            let schemes = try await listSchemes(at: projectPath)
            guard let first = schemes.first else {
                throw BuildError.schemeNotFound("No schemes found in project")
            }
            schemeName = first.name
        }
        args += ["-scheme", schemeName]

        args += ["-configuration", configuration]

        // Handle destination
        if let destination = destination {
            args += ["-destination", destination]
        } else if let platform = destinationPlatform {
            args += ["-destination", buildDestinationString(for: platform)]
        } else {
            // Default to macOS
            args += ["-destination", "platform=macOS"]
        }

        if clean {
            args += ["clean"]
        }
        args += ["build"]

        let result = try await ProcessRunner.xcodebuild(
            arguments: args,
            timeout: 900  // 15 minutes for Xcode builds
        )

        let combinedOutput = result.stdout + "\n" + result.stderr
        let (errors, warnings) = OutputParser.parseBuildOutput(combinedOutput)
        let success = result.exitCode == 0 &&
            (combinedOutput.contains("BUILD SUCCEEDED") || errors.isEmpty)

        return BuildResult(
            success: success,
            duration: result.duration,
            errors: errors,
            warnings: warnings,
            buildLogPath: nil
        )
    }

    /// Run Xcode tests
    func xcodeTest(
        at projectPath: String,
        scheme: String? = nil,
        destination: String? = nil,
        destinationPlatform: String? = nil,
        testPlan: String? = nil,
        onlyTesting: [String]? = nil,
        skipTesting: [String]? = nil,
        enableCodeCoverage: Bool = false
    ) async throws -> TestResult {
        let (projectArg, projectValue) = try await resolveXcodeProject(projectPath)

        var args = [projectArg, projectValue]

        // Get or detect scheme
        let schemeName: String
        if let scheme = scheme {
            schemeName = scheme
        } else {
            let schemes = try await listSchemes(at: projectPath)
            guard let first = schemes.first else {
                throw BuildError.schemeNotFound("No schemes found in project")
            }
            schemeName = first.name
        }
        args += ["-scheme", schemeName]

        // Handle destination
        if let destination = destination {
            args += ["-destination", destination]
        } else if let platform = destinationPlatform {
            args += ["-destination", buildDestinationString(for: platform)]
        } else {
            args += ["-destination", "platform=macOS"]
        }

        if let testPlan = testPlan {
            args += ["-testPlan", testPlan]
        }

        if let onlyTesting = onlyTesting {
            for test in onlyTesting {
                args += ["-only-testing", test]
            }
        }

        if let skipTesting = skipTesting {
            for test in skipTesting {
                args += ["-skip-testing", test]
            }
        }

        if enableCodeCoverage {
            args += ["-enableCodeCoverage", "YES"]
        }

        args += ["test"]

        let result = try await ProcessRunner.xcodebuild(
            arguments: args,
            timeout: 900  // 15 minutes for tests
        )

        let combinedOutput = result.stdout + "\n" + result.stderr
        return OutputParser.parseTestOutput(combinedOutput)
    }

    /// List schemes for a project
    func listSchemes(at projectPath: String) async throws -> [Scheme] {
        // Check if it's a Swift package
        let packageSwift = projectPath.hasSuffix("Package.swift")
            ? projectPath
            : "\(projectPath)/Package.swift"

        if fileManager.fileExists(atPath: packageSwift) {
            // For SPM, use swift package describe
            let result = try await ProcessRunner.swift(
                arguments: ["package", "describe", "--type", "json"],
                workingDirectory: projectPath.hasSuffix("Package.swift")
                    ? URL(fileURLWithPath: projectPath).deletingLastPathComponent().path
                    : projectPath
            )

            if let data = result.stdout.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["name"] as? String {
                // SPM packages have the package name as their "scheme"
                return [Scheme(name: name, isShared: true)]
            }
        }

        // For Xcode projects
        let (projectArg, projectValue) = try await resolveXcodeProject(projectPath)

        let result = try await ProcessRunner.xcodebuild(
            arguments: [projectArg, projectValue, "-list", "-json"],
            timeout: 30
        )

        return OutputParser.parseSchemesList(result.stdout)
    }

    /// List available destinations for a project/scheme
    func listDestinations(
        at projectPath: String,
        scheme: String? = nil,
        platform: String? = nil
    ) async throws -> [Destination] {
        let (projectArg, projectValue) = try await resolveXcodeProject(projectPath)

        var args = [projectArg, projectValue]

        if let scheme = scheme {
            args += ["-scheme", scheme]
        } else {
            // Try to get first scheme
            let schemes = try await listSchemes(at: projectPath)
            if let first = schemes.first {
                args += ["-scheme", first.name]
            }
        }

        args += ["-showdestinations"]

        let result = try await ProcessRunner.xcodebuild(
            arguments: args,
            timeout: 30
        )

        var destinations = OutputParser.parseDestinations(result.stdout + result.stderr)

        // Filter by platform if specified
        if let platform = platform {
            let platformLower = platform.lowercased()
            destinations = destinations.filter {
                $0.platform.lowercased().contains(platformLower)
            }
        }

        return destinations
    }

    // MARK: - Helper Methods

    private func resolvePackageDirectory(_ path: String) throws -> String {
        if path.hasSuffix("Package.swift") {
            let dir = URL(fileURLWithPath: path).deletingLastPathComponent().path
            guard fileManager.fileExists(atPath: path) else {
                throw BuildError.projectNotFound(path)
            }
            return dir
        }

        let packagePath = "\(path)/Package.swift"
        if fileManager.fileExists(atPath: packagePath) {
            return path
        }

        throw BuildError.projectNotFound("No Package.swift found at \(path)")
    }

    private func resolveXcodeProject(_ path: String) async throws -> (arg: String, value: String) {
        // Check for workspace
        if path.hasSuffix(".xcworkspace") {
            guard fileManager.fileExists(atPath: path) else {
                throw BuildError.projectNotFound(path)
            }
            return ("-workspace", path)
        }

        // Check for project
        if path.hasSuffix(".xcodeproj") {
            guard fileManager.fileExists(atPath: path) else {
                throw BuildError.projectNotFound(path)
            }
            return ("-project", path)
        }

        // Look for workspace first, then project in directory
        let workspaces = try? fileManager.contentsOfDirectory(atPath: path)
            .filter { $0.hasSuffix(".xcworkspace") }
        if let workspace = workspaces?.first {
            return ("-workspace", "\(path)/\(workspace)")
        }

        let projects = try? fileManager.contentsOfDirectory(atPath: path)
            .filter { $0.hasSuffix(".xcodeproj") }
        if let project = projects?.first {
            return ("-project", "\(path)/\(project)")
        }

        // Maybe it's a Swift package that can be built with xcodebuild
        let packagePath = "\(path)/Package.swift"
        if fileManager.fileExists(atPath: packagePath) {
            // Generate Xcode project from package
            _ = try? await ProcessRunner.swift(
                arguments: ["package", "generate-xcodeproj"],
                workingDirectory: path
            )

            let generatedProjects = try? fileManager.contentsOfDirectory(atPath: path)
                .filter { $0.hasSuffix(".xcodeproj") }
            if let project = generatedProjects?.first {
                return ("-project", "\(path)/\(project)")
            }
        }

        throw BuildError.invalidProject("No Xcode project or workspace found at \(path)")
    }

    private func buildDestinationString(for platform: String) -> String {
        switch platform.lowercased() {
        case "ios simulator", "iphone simulator", "ios sim":
            return "platform=iOS Simulator,name=iPhone 16 Pro"
        case "ios", "iphone":
            return "generic/platform=iOS"
        case "macos", "mac":
            return "platform=macOS"
        case "tvos simulator", "tvos sim":
            return "platform=tvOS Simulator,name=Apple TV"
        case "tvos":
            return "generic/platform=tvOS"
        case "watchos simulator", "watchos sim":
            return "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)"
        case "watchos":
            return "generic/platform=watchOS"
        case "visionos simulator", "visionos sim":
            return "platform=visionOS Simulator,name=Apple Vision Pro"
        case "visionos":
            return "generic/platform=visionOS"
        default:
            return "platform=macOS"
        }
    }
}
