import Foundation

/// Service for parsing and analyzing project dependencies
actor DependencyService {
    private let fileManager = FileManager.default
    private let symbolGraphService = SymbolGraphService()

    /// Full dependency information for a project
    struct ProjectDependencies: Codable, Sendable {
        let packageName: String
        let dependencies: [Dependency]
        let targets: [TargetDependencies]
        let resolvedVersions: [String: ResolvedVersion]
    }

    struct Dependency: Codable, Sendable {
        let name: String
        let url: String?
        let requirement: String?
        let products: [String]
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

    /// Get all dependencies for an SPM project
    func getDependencies(at projectPath: String) async throws -> ProjectDependencies {
        let packageDir = projectPath.hasSuffix("Package.swift")
            ? (projectPath as NSString).deletingLastPathComponent
            : projectPath

        // Get package manifest
        let manifest = try await dumpPackageManifest(at: packageDir)

        // Get resolved versions
        let resolved = try await parsePackageResolved(at: packageDir)

        // Parse dependencies
        let dependencies = parseDependencies(from: manifest)
        let targets = parseTargetDependencies(from: manifest)

        return ProjectDependencies(
            packageName: manifest["name"] as? String ?? "Unknown",
            dependencies: dependencies,
            targets: targets,
            resolvedVersions: resolved
        )
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
        process.waitUntilExit()

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

    private func parseDependencies(from manifest: [String: Any]) -> [Dependency] {
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
                    products: []
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
                    products: []
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
        process.waitUntilExit()

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
