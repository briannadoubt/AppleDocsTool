import Foundation

/// Parser for Swift Package Manager projects
actor SPMParser {
    private let fileManager = FileManager.default

    /// Parse a Package.swift and return project information
    func parsePackage(at path: String) async throws -> Project {
        let packagePath = path.hasSuffix("Package.swift") ? path : "\(path)/Package.swift"

        guard fileManager.fileExists(atPath: packagePath) else {
            throw SPMParserError.packageNotFound(packagePath)
        }

        let packageDir = (packagePath as NSString).deletingLastPathComponent
        let manifest = try await dumpPackageManifest(at: packageDir)

        let targets = manifest.targets.map { target -> Project.Target in
            let sourcePath = target.path ?? "Sources/\(target.name)"
            let fullSourcePath = "\(packageDir)/\(sourcePath)"

            let dependencies = target.dependencies?.compactMap { dep -> String? in
                dep.target?.first ?? dep.product?.first
            } ?? []

            return Project.Target(
                name: target.name,
                moduleName: target.name,
                sourcePaths: [fullSourcePath],
                dependencies: dependencies
            )
        }

        return Project(
            path: packageDir,
            type: .spm,
            name: manifest.name,
            targets: targets
        )
    }

    /// Get all target names from a package
    func getTargetNames(at path: String) async throws -> [String] {
        let project = try await parsePackage(at: path)
        return project.targets.map { $0.name }
    }

    private func dumpPackageManifest(at path: String) async throws -> SPMManifest {
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

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SPMParserError.dumpFailed(errorMessage)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        // Parse the JSON output
        guard let json = try JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
            throw SPMParserError.invalidManifest("Could not parse package manifest as JSON")
        }

        let name = json["name"] as? String ?? "Unknown"
        var targets: [SPMManifest.SPMTarget] = []

        if let targetsArray = json["targets"] as? [[String: Any]] {
            for targetData in targetsArray {
                let targetName = targetData["name"] as? String ?? "Unknown"
                let targetType = targetData["type"] as? String ?? "regular"
                let targetPath = targetData["path"] as? String
                let sources = targetData["sources"] as? [String]

                var dependencies: [SPMManifest.SPMTarget.SPMDependency] = []
                if let depsArray = targetData["dependencies"] as? [[String: Any]] {
                    for depData in depsArray {
                        if let targetDep = depData["target"] as? [String: String],
                           let depName = targetDep["name"] {
                            dependencies.append(.init(target: [depName], product: nil))
                        } else if let productDep = depData["product"] as? [String: Any],
                                  let productName = productDep["name"] as? String {
                            dependencies.append(.init(target: nil, product: [productName]))
                        }
                    }
                }

                targets.append(SPMManifest.SPMTarget(
                    name: targetName,
                    type: targetType,
                    path: targetPath,
                    sources: sources,
                    dependencies: dependencies.isEmpty ? nil : dependencies
                ))
            }
        }

        return SPMManifest(name: name, targets: targets)
    }
}

enum SPMParserError: Error, LocalizedError {
    case packageNotFound(String)
    case dumpFailed(String)
    case invalidManifest(String)

    var errorDescription: String? {
        switch self {
        case .packageNotFound(let path):
            return "Package.swift not found at: \(path)"
        case .dumpFailed(let message):
            return "Failed to dump package manifest: \(message)"
        case .invalidManifest(let message):
            return "Invalid package manifest: \(message)"
        }
    }
}
