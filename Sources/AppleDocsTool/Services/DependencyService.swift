import Foundation

/// Service for parsing and analyzing project dependencies
actor DependencyService {
    private let fileManager = FileManager.default
    private let symbolGraphService = SymbolGraphService()

    /// Type of dependency manager detected
    enum DependencyManagerType: String, Codable, Sendable {
        case spm = "Swift Package Manager"
        case xcodeSPM = "Xcode SPM"
        case cocoapods = "CocoaPods"
        case carthage = "Carthage"
    }

    /// Full dependency information for a project
    struct ProjectDependencies: Codable, Sendable {
        let packageName: String
        let projectType: String
        let dependencyManagers: [String]
        let dependencies: [Dependency]
        let targets: [TargetDependencies]
        let resolvedVersions: [String: ResolvedVersion]
    }

    struct Dependency: Codable, Sendable {
        let name: String
        let url: String?
        let requirement: String?
        let products: [String]
        let source: String // "spm", "xcode-spm", "cocoapods", "carthage"
    }

    struct TargetDependencies: Codable, Sendable {
        let name: String
        let type: String
        let dependencies: [TargetDependency]
    }

    struct TargetDependency: Codable, Sendable {
        let name: String
        let kind: String // "target", "product", "byName"
        let package: String?
    }

    struct ResolvedVersion: Codable, Sendable {
        let package: String
        let repositoryURL: String?
        let version: String?
        let branch: String?
        let revision: String
    }

    /// Get all dependencies for any project type (SPM or Xcode)
    func getDependencies(at projectPath: String) async throws -> ProjectDependencies {
        // Detect project type
        let isXcodeProject = projectPath.hasSuffix(".xcodeproj") ||
                            projectPath.hasSuffix(".xcworkspace") ||
                            fileManager.fileExists(atPath: "\(projectPath)/project.pbxproj")

        let isXcodeWorkspace = projectPath.hasSuffix(".xcworkspace")

        let isSPMProject = projectPath.hasSuffix("Package.swift") ||
                          fileManager.fileExists(atPath: "\(projectPath)/Package.swift")

        if isSPMProject && !isXcodeProject {
            return try await getSPMDependencies(at: projectPath)
        } else if isXcodeProject || isXcodeWorkspace {
            return try await getXcodeDependencies(at: projectPath)
        } else {
            // Try to detect from directory contents
            let contents = try fileManager.contentsOfDirectory(atPath: projectPath)
            if contents.contains("Package.swift") {
                return try await getSPMDependencies(at: projectPath)
            } else if contents.first(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) != nil {
                return try await getXcodeDependencies(at: projectPath)
            }
            throw DependencyError.invalidManifest
        }
    }

    /// Get dependencies for a pure SPM project
    private func getSPMDependencies(at projectPath: String) async throws -> ProjectDependencies {
        let packageDir = projectPath.hasSuffix("Package.swift")
            ? (projectPath as NSString).deletingLastPathComponent
            : projectPath

        // Get package manifest
        let manifest = try await dumpPackageManifest(at: packageDir)

        // Get resolved versions
        let resolved = try await parsePackageResolved(at: packageDir)

        // Parse dependencies
        let dependencies = parseDependencies(from: manifest, source: "spm")
        let targets = parseTargetDependencies(from: manifest)

        return ProjectDependencies(
            packageName: manifest["name"] as? String ?? "Unknown",
            projectType: "Swift Package",
            dependencyManagers: ["Swift Package Manager"],
            dependencies: dependencies,
            targets: targets,
            resolvedVersions: resolved
        )
    }

    /// Get dependencies for an Xcode project
    private func getXcodeDependencies(at projectPath: String) async throws -> ProjectDependencies {
        var projectName = "Unknown"
        var projectDir = projectPath
        var dependencyManagers: [String] = []
        var allDependencies: [Dependency] = []
        var allResolved: [String: ResolvedVersion] = [:]

        // Determine project name and directory
        if projectPath.hasSuffix(".xcodeproj") {
            projectName = (projectPath as NSString).lastPathComponent.replacingOccurrences(of: ".xcodeproj", with: "")
            projectDir = (projectPath as NSString).deletingLastPathComponent
        } else if projectPath.hasSuffix(".xcworkspace") {
            projectName = (projectPath as NSString).lastPathComponent.replacingOccurrences(of: ".xcworkspace", with: "")
            projectDir = (projectPath as NSString).deletingLastPathComponent
        } else {
            // Find project in directory
            let contents = try fileManager.contentsOfDirectory(atPath: projectPath)
            if let proj = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
                projectName = proj.replacingOccurrences(of: ".xcworkspace", with: "")
            } else if let proj = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
                projectName = proj.replacingOccurrences(of: ".xcodeproj", with: "")
            }
        }

        // Check for SPM dependencies in Xcode project
        let spmResolved = try await parseXcodeSPMResolved(at: projectPath)
        if !spmResolved.isEmpty {
            dependencyManagers.append("Swift Package Manager")
            allResolved.merge(spmResolved) { _, new in new }

            // Convert resolved to dependencies
            for (_, resolved) in spmResolved {
                allDependencies.append(Dependency(
                    name: resolved.package,
                    url: resolved.repositoryURL,
                    requirement: resolved.version ?? resolved.branch,
                    products: [],
                    source: "xcode-spm"
                ))
            }
        }

        // Check for CocoaPods (just detect, don't fully parse yet)
        let podfileLock = "\(projectDir)/Podfile.lock"
        if fileManager.fileExists(atPath: podfileLock) {
            dependencyManagers.append("CocoaPods")
            let podDeps = parsePodfileLock(at: podfileLock)
            allDependencies.append(contentsOf: podDeps)
        }

        // Check for Carthage (just detect, don't fully parse yet)
        let cartfileResolved = "\(projectDir)/Cartfile.resolved"
        if fileManager.fileExists(atPath: cartfileResolved) {
            dependencyManagers.append("Carthage")
            let carthageDeps = parseCartfileResolved(at: cartfileResolved)
            allDependencies.append(contentsOf: carthageDeps)
        }

        if dependencyManagers.isEmpty {
            dependencyManagers.append("None detected")
        }

        return ProjectDependencies(
            packageName: projectName,
            projectType: projectPath.hasSuffix(".xcworkspace") ? "Xcode Workspace" : "Xcode Project",
            dependencyManagers: dependencyManagers,
            dependencies: allDependencies,
            targets: [], // Would need to parse pbxproj for this
            resolvedVersions: allResolved
        )
    }

    /// Parse Package.resolved from Xcode project's SPM location
    private func parseXcodeSPMResolved(at projectPath: String) async throws -> [String: ResolvedVersion] {
        var possiblePaths: [String] = []

        if projectPath.hasSuffix(".xcworkspace") {
            // Workspace: .xcworkspace/xcshareddata/swiftpm/Package.resolved
            possiblePaths.append("\(projectPath)/xcshareddata/swiftpm/Package.resolved")
        } else if projectPath.hasSuffix(".xcodeproj") {
            // Project: .xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
            possiblePaths.append("\(projectPath)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        } else {
            // Directory - look for workspace or project
            let contents = try fileManager.contentsOfDirectory(atPath: projectPath)
            if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
                possiblePaths.append("\(projectPath)/\(workspace)/xcshareddata/swiftpm/Package.resolved")
            }
            if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
                possiblePaths.append("\(projectPath)/\(project)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
            }
        }

        // Try each possible path
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                return try parsePackageResolvedFile(at: path)
            }
        }

        return [:]
    }

    /// Parse a Package.resolved file at a specific path
    private func parsePackageResolvedFile(at path: String) throws -> [String: ResolvedVersion] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var resolved: [String: ResolvedVersion] = [:]

        // Handle v1, v2, and v3 formats
        if let version = json["version"] as? Int, version >= 2 {
            // v2/v3 format
            if let pins = json["pins"] as? [[String: Any]] {
                for pin in pins {
                    guard let identity = pin["identity"] as? String else { continue }
                    let location = pin["location"] as? String
                    let state = pin["state"] as? [String: Any]

                    resolved[identity] = ResolvedVersion(
                        package: identity,
                        repositoryURL: location,
                        version: state?["version"] as? String,
                        branch: state?["branch"] as? String,
                        revision: state?["revision"] as? String ?? ""
                    )
                }
            }
        } else if let object = json["object"] as? [String: Any],
                  let pins = object["pins"] as? [[String: Any]] {
            // v1 format
            for pin in pins {
                guard let package = pin["package"] as? String else { continue }
                let repositoryURL = pin["repositoryURL"] as? String
                let state = pin["state"] as? [String: Any]

                resolved[package.lowercased()] = ResolvedVersion(
                    package: package,
                    repositoryURL: repositoryURL,
                    version: state?["version"] as? String,
                    branch: state?["branch"] as? String,
                    revision: state?["revision"] as? String ?? ""
                )
            }
        }

        return resolved
    }

    /// Basic CocoaPods Podfile.lock parsing
    private func parsePodfileLock(at path: String) -> [Dependency] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }

        var dependencies: [Dependency] = []
        var inPods = false

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "PODS:" {
                inPods = true
                continue
            } else if trimmed.hasPrefix("DEPENDENCIES:") || trimmed.hasPrefix("SPEC REPOS:") {
                inPods = false
                continue
            }

            if inPods && trimmed.hasPrefix("- ") {
                // Parse pod entry like "- Alamofire (5.8.1):"
                let podLine = String(trimmed.dropFirst(2))
                let parts = podLine.components(separatedBy: " (")
                if let name = parts.first?.trimmingCharacters(in: .whitespaces),
                   !name.isEmpty && !name.contains("/") { // Skip subspecs
                    var version: String?
                    if parts.count > 1 {
                        version = parts[1].replacingOccurrences(of: "):", with: "")
                                         .replacingOccurrences(of: ")", with: "")
                    }
                    // Avoid duplicates
                    if !dependencies.contains(where: { $0.name == name }) {
                        dependencies.append(Dependency(
                            name: name,
                            url: nil,
                            requirement: version,
                            products: [],
                            source: "cocoapods"
                        ))
                    }
                }
            }
        }

        return dependencies
    }

    /// Basic Carthage Cartfile.resolved parsing
    private func parseCartfileResolved(at path: String) -> [Dependency] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }

        var dependencies: [Dependency] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Format: github "owner/repo" "version"
            // or: git "url" "version"
            let parts = trimmed.components(separatedBy: "\" \"")
            guard parts.count >= 2 else { continue }

            let sourceAndRepo = parts[0]
            let version = parts[1].replacingOccurrences(of: "\"", with: "")

            var name: String
            var url: String?

            if sourceAndRepo.hasPrefix("github \"") {
                let repo = sourceAndRepo.replacingOccurrences(of: "github \"", with: "")
                name = repo.components(separatedBy: "/").last ?? repo
                url = "https://github.com/\(repo)"
            } else if sourceAndRepo.hasPrefix("git \"") {
                let gitUrl = sourceAndRepo.replacingOccurrences(of: "git \"", with: "")
                name = URL(string: gitUrl)?.lastPathComponent.replacingOccurrences(of: ".git", with: "") ?? gitUrl
                url = gitUrl
            } else {
                continue
            }

            dependencies.append(Dependency(
                name: name,
                url: url,
                requirement: version,
                products: [],
                source: "carthage"
            ))
        }

        return dependencies
    }

    /// Extract symbols from all dependencies
    func extractDependencySymbols(
        at projectPath: String,
        minimumAccessLevel: AccessLevel = .public
    ) async throws -> [String: [Symbol]] {
        let packageDir = projectPath.hasSuffix("Package.swift")
            ? (projectPath as NSString).deletingLastPathComponent
            : projectPath

        // Build the package first to ensure all dependencies are compiled
        try await buildPackage(at: packageDir)

        // Get list of all dependency modules
        let dependencyModules = try await listDependencyModules(at: packageDir)

        var symbolsByModule: [String: [Symbol]] = [:]

        for moduleName in dependencyModules {
            do {
                let symbols = try await symbolGraphService.extractSymbols(
                    moduleName: moduleName,
                    searchPaths: [
                        "\(packageDir)/.build/debug",
                        "\(packageDir)/.build/release",
                        "\(packageDir)/.build/checkouts"
                    ],
                    minimumAccessLevel: minimumAccessLevel
                )
                if !symbols.isEmpty {
                    symbolsByModule[moduleName] = symbols
                }
            } catch {
                // Skip modules that fail to extract (might be system modules)
                continue
            }
        }

        return symbolsByModule
    }

    /// List all available modules from dependencies
    func listDependencyModules(at packageDir: String) async throws -> [String] {
        var modules: Set<String> = []

        // Get from Package.resolved
        let resolved = try await parsePackageResolved(at: packageDir)
        for (name, _) in resolved {
            modules.insert(name)
        }

        // Also scan .build/checkouts for actual module names
        let checkoutsPath = "\(packageDir)/.build/checkouts"
        if fileManager.fileExists(atPath: checkoutsPath) {
            let checkouts = try fileManager.contentsOfDirectory(atPath: checkoutsPath)
            for checkout in checkouts {
                let packageSwift = "\(checkoutsPath)/\(checkout)/Package.swift"
                if fileManager.fileExists(atPath: packageSwift) {
                    // Get target names from this package
                    if let manifest = try? await dumpPackageManifest(at: "\(checkoutsPath)/\(checkout)"),
                       let targets = manifest["targets"] as? [[String: Any]] {
                        for target in targets {
                            if let name = target["name"] as? String,
                               let type = target["type"] as? String,
                               type != "test" {
                                modules.insert(name)
                            }
                        }
                    }
                }
            }
        }

        // Scan built modules in .build/debug
        let debugPath = "\(packageDir)/.build/debug"
        if fileManager.fileExists(atPath: debugPath) {
            let contents = try? fileManager.contentsOfDirectory(atPath: debugPath)
            for item in contents ?? [] {
                if item.hasSuffix(".swiftmodule") {
                    let moduleName = item.replacingOccurrences(of: ".swiftmodule", with: "")
                    modules.insert(moduleName)
                }
            }
        }

        return Array(modules).sorted()
    }

    // MARK: - Private Methods

    private func dumpPackageManifest(at path: String) async throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["package", "dump-package"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Add timeout (30 seconds for dump-package)
        let timeout: TimeInterval = 30
        let startTime = Date()
        while process.isRunning {
            if Date().timeIntervalSince(startTime) > timeout {
                process.terminate()
                throw DependencyError.invalidManifest
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        guard let json = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
            throw DependencyError.invalidManifest
        }

        return json
    }

    private func parsePackageResolved(at packageDir: String) async throws -> [String: ResolvedVersion] {
        // Try Package.resolved (SPM 5.6+) or Package.resolved in the old location
        let possiblePaths = [
            "\(packageDir)/Package.resolved",
            "\(packageDir)/.build/Package.resolved"
        ]

        var resolvedData: Data?
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                resolvedData = try? Data(contentsOf: URL(fileURLWithPath: path))
                break
            }
        }

        guard let data = resolvedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var resolved: [String: ResolvedVersion] = [:]

        // Handle both v1 and v2/v3 formats
        if let version = json["version"] as? Int {
            if version >= 2 {
                // v2/v3 format
                if let pins = json["pins"] as? [[String: Any]] {
                    for pin in pins {
                        guard let identity = pin["identity"] as? String else { continue }
                        let location = pin["location"] as? String
                        let state = pin["state"] as? [String: Any]

                        resolved[identity] = ResolvedVersion(
                            package: identity,
                            repositoryURL: location,
                            version: state?["version"] as? String,
                            branch: state?["branch"] as? String,
                            revision: state?["revision"] as? String ?? ""
                        )
                    }
                }
            }
        } else if let object = json["object"] as? [String: Any],
                  let pins = object["pins"] as? [[String: Any]] {
            // v1 format
            for pin in pins {
                guard let package = pin["package"] as? String else { continue }
                let repositoryURL = pin["repositoryURL"] as? String
                let state = pin["state"] as? [String: Any]

                resolved[package.lowercased()] = ResolvedVersion(
                    package: package,
                    repositoryURL: repositoryURL,
                    version: state?["version"] as? String,
                    branch: state?["branch"] as? String,
                    revision: state?["revision"] as? String ?? ""
                )
            }
        }

        return resolved
    }

    private func parseDependencies(from manifest: [String: Any], source: String) -> [Dependency] {
        guard let deps = manifest["dependencies"] as? [[String: Any]] else {
            return []
        }

        return deps.compactMap { dep -> Dependency? in
            // Handle different dependency formats
            if let sourceControl = dep["sourceControl"] as? [[String: Any]],
               let first = sourceControl.first {
                let identity = first["identity"] as? String ?? "unknown"
                let location = first["location"] as? [String: Any]
                let url = location?["remote"] as? [[String: Any]]
                let urlString = url?.first?["urlString"] as? String

                var requirement: String?
                if let req = first["requirement"] as? [String: Any] {
                    if let range = req["range"] as? [[String: Any]],
                       let first = range.first {
                        let lower = first["lowerBound"] as? String ?? ""
                        let upper = first["upperBound"] as? String ?? ""
                        requirement = "\(lower)..<\(upper)"
                    } else if let exact = req["exact"] as? [String] {
                        requirement = exact.first
                    } else if let branch = req["branch"] as? [String] {
                        requirement = "branch: \(branch.first ?? "")"
                    }
                }

                return Dependency(
                    name: identity,
                    url: urlString,
                    requirement: requirement,
                    products: [],
                    source: source
                )
            }

            // Older format
            if let url = dep["url"] as? String {
                let name = dep["name"] as? String ??
                    URL(string: url)?.lastPathComponent.replacingOccurrences(of: ".git", with: "") ?? "unknown"
                return Dependency(
                    name: name,
                    url: url,
                    requirement: nil,
                    products: [],
                    source: source
                )
            }

            return nil
        }
    }

    private func parseTargetDependencies(from manifest: [String: Any]) -> [TargetDependencies] {
        guard let targets = manifest["targets"] as? [[String: Any]] else {
            return []
        }

        return targets.compactMap { target -> TargetDependencies? in
            guard let name = target["name"] as? String else { return nil }
            let type = target["type"] as? String ?? "regular"

            var deps: [TargetDependency] = []

            if let dependencies = target["dependencies"] as? [[String: Any]] {
                for dep in dependencies {
                    if let targetDep = dep["target"] as? [String: Any],
                       let depName = targetDep["name"] as? String {
                        deps.append(TargetDependency(name: depName, kind: "target", package: nil))
                    } else if let productDep = dep["product"] as? [String: Any],
                              let depName = productDep["name"] as? String {
                        let package = productDep["package"] as? String
                        deps.append(TargetDependency(name: depName, kind: "product", package: package))
                    } else if let byName = dep["byName"] as? [String: Any],
                              let depName = byName["name"] as? String {
                        deps.append(TargetDependency(name: depName, kind: "byName", package: nil))
                    }
                }
            }

            return TargetDependencies(name: name, type: type, dependencies: deps)
        }
    }

    private func buildPackage(at path: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["build", "--package-path", path]
        process.currentDirectoryURL = URL(fileURLWithPath: path)

        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        try process.run()

        // Add timeout for build (5 minutes max)
        let timeout: TimeInterval = 300
        let startTime = Date()
        while process.isRunning {
            if Date().timeIntervalSince(startTime) > timeout {
                process.terminate()
                // Don't throw - we still want to try extracting what we can
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Don't throw on build failure - we still want to try extracting what we can
    }
}

enum DependencyError: Error, LocalizedError {
    case invalidManifest
    case resolvedNotFound
    case buildFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "Could not parse Package.swift manifest"
        case .resolvedNotFound:
            return "Package.resolved not found"
        case .buildFailed(let message):
            return "Build failed: \(message)"
        }
    }
}
