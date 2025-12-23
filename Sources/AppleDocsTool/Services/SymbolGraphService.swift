import Foundation

/// Service for extracting symbols using swift-symbolgraph-extract
actor SymbolGraphService {
    private let fileManager = FileManager.default

    /// Extract symbols from a Swift module
    func extractSymbols(
        moduleName: String,
        searchPaths: [String],
        minimumAccessLevel: AccessLevel = .public,
        target: String? = nil
    ) async throws -> [Symbol] {
        let outputDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: outputDir) }

        let sdkPath = try await getSDKPath()
        let targetTriple: String
        if let target = target {
            targetTriple = target
        } else {
            targetTriple = try await getDefaultTarget()
        }

        var arguments = [
            "symbolgraph-extract",
            "-module-name", moduleName,
            "-minimum-access-level", accessLevelString(minimumAccessLevel),
            "-output-dir", outputDir.path,
            "-target", targetTriple,
            "-sdk", sdkPath,
            "-pretty-print"
        ]

        for path in searchPaths {
            arguments.append(contentsOf: ["-I", path])
            arguments.append(contentsOf: ["-F", path])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Timeout for symbol extraction (2 minutes)
        let timeout: TimeInterval = 120
        let startTime = Date()
        while process.isRunning {
            if Date().timeIntervalSince(startTime) > timeout {
                process.terminate()
                throw SymbolGraphError.extractionFailed("Symbol extraction timed out after \(Int(timeout)) seconds")
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SymbolGraphError.extractionFailed(errorMessage)
        }

        return try parseSymbolGraphs(in: outputDir, moduleName: moduleName)
    }

    /// Extract symbols from a built Swift package
    func extractFromPackage(
        at packagePath: String,
        targetName: String,
        minimumAccessLevel: AccessLevel = .public
    ) async throws -> [Symbol] {
        // First build the package to generate module files
        let buildDir = try await buildPackage(at: packagePath)

        let searchPaths = [
            "\(buildDir)/debug",
            "\(buildDir)/release",
            "\(packagePath)/.build/debug",
            "\(packagePath)/.build/release"
        ]

        return try await extractSymbols(
            moduleName: targetName,
            searchPaths: searchPaths,
            minimumAccessLevel: minimumAccessLevel
        )
    }

    /// Extract symbols from a built Xcode project
    func extractFromXcodeProject(
        at projectPath: String,
        targetName: String,
        minimumAccessLevel: AccessLevel = .public
    ) async throws -> [Symbol] {
        // Find DerivedData for this project
        let searchPaths = try findXcodeBuildPaths(projectPath: projectPath, targetName: targetName)

        if searchPaths.isEmpty {
            throw SymbolGraphError.extractionFailed("No Xcode build products found. Please build the project in Xcode first.")
        }

        return try await extractSymbols(
            moduleName: targetName,
            searchPaths: searchPaths,
            minimumAccessLevel: minimumAccessLevel
        )
    }

    /// Find Xcode DerivedData build paths for a project
    private func findXcodeBuildPaths(projectPath: String, targetName: String) throws -> [String] {
        var searchPaths: [String] = []

        // Get project name from path
        let projectName: String
        if projectPath.hasSuffix(".xcodeproj") {
            projectName = (projectPath as NSString).lastPathComponent.replacingOccurrences(of: ".xcodeproj", with: "")
        } else if projectPath.hasSuffix(".xcworkspace") {
            projectName = (projectPath as NSString).lastPathComponent.replacingOccurrences(of: ".xcworkspace", with: "")
        } else {
            // Try to find project in directory
            let contents = try fileManager.contentsOfDirectory(atPath: projectPath)
            if let proj = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
                projectName = proj.replacingOccurrences(of: ".xcodeproj", with: "")
            } else if let ws = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
                projectName = ws.replacingOccurrences(of: ".xcworkspace", with: "")
            } else {
                projectName = (projectPath as NSString).lastPathComponent
            }
        }

        // Default DerivedData location
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        let derivedDataPath = "\(homeDir)/Library/Developer/Xcode/DerivedData"

        if fileManager.fileExists(atPath: derivedDataPath) {
            // Find project's DerivedData folder (format: ProjectName-randomhash)
            let contents = try? fileManager.contentsOfDirectory(atPath: derivedDataPath)
            for folder in contents ?? [] {
                if folder.hasPrefix(projectName) || folder.lowercased().hasPrefix(projectName.lowercased()) {
                    let buildProductsPath = "\(derivedDataPath)/\(folder)/Build/Products"
                    if fileManager.fileExists(atPath: buildProductsPath) {
                        // Add all configuration folders (Debug-iphonesimulator, Release-iphoneos, etc.)
                        if let configs = try? fileManager.contentsOfDirectory(atPath: buildProductsPath) {
                            for config in configs {
                                let configPath = "\(buildProductsPath)/\(config)"
                                searchPaths.append(configPath)

                                // Also check for framework modules inside
                                let frameworkPath = "\(configPath)/\(targetName).framework/Modules"
                                if fileManager.fileExists(atPath: frameworkPath) {
                                    searchPaths.append(frameworkPath)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Also check for build folder next to project (custom DerivedData location)
        let projectDir = projectPath.hasSuffix(".xcodeproj") || projectPath.hasSuffix(".xcworkspace")
            ? (projectPath as NSString).deletingLastPathComponent
            : projectPath
        let localBuild = "\(projectDir)/build"
        if fileManager.fileExists(atPath: localBuild) {
            if let configs = try? fileManager.contentsOfDirectory(atPath: localBuild) {
                for config in configs {
                    searchPaths.append("\(localBuild)/\(config)")
                }
            }
        }

        return searchPaths
    }

    private func buildPackage(at path: String) async throws -> String {
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
                throw SymbolGraphError.buildFailed("Build timed out after \(Int(timeout)) seconds")
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Build failed"
            throw SymbolGraphError.buildFailed(errorMessage)
        }

        return "\(path)/.build"
    }

    private func getSDKPath() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--show-sdk-path"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        // Quick command - 10 second timeout
        let timeout: TimeInterval = 10
        let startTime = Date()
        while process.isRunning {
            if Date().timeIntervalSince(startTime) > timeout {
                process.terminate()
                throw SymbolGraphError.sdkNotFound
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw SymbolGraphError.sdkNotFound
        }
        return path
    }

    private func getDefaultTarget() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["-print-target-info"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        // Quick command - 10 second timeout
        let timeout: TimeInterval = 10
        let startTime = Date()
        while process.isRunning {
            if Date().timeIntervalSince(startTime) > timeout {
                process.terminate()
                // Fall back to default
                return "arm64-apple-macosx13.0"
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let target = json["target"] as? [String: Any],
           let triple = target["unversionedTriple"] as? String {
            return triple
        }

        // Fallback for macOS
        return "arm64-apple-macosx13.0"
    }

    private func accessLevelString(_ level: AccessLevel) -> String {
        switch level {
        case .private: return "private"
        case .fileprivate: return "fileprivate"
        case .internal: return "internal"
        case .package: return "package"
        case .public: return "public"
        case .open: return "open"
        }
    }

    private func parseSymbolGraphs(in directory: URL, moduleName: String) throws -> [Symbol] {
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let symbolGraphFiles = contents.filter { $0.pathExtension == "json" }

        var symbols: [Symbol] = []

        for file in symbolGraphFiles {
            let data = try Data(contentsOf: file)
            let parsed = try parseSymbolGraph(data: data, moduleName: moduleName)
            symbols.append(contentsOf: parsed)
        }

        return symbols
    }

    private func parseSymbolGraph(data: Data, moduleName: String) throws -> [Symbol] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let symbolsArray = json["symbols"] as? [[String: Any]] else {
            return []
        }

        var symbols: [Symbol] = []

        for symbolData in symbolsArray {
            guard let identifier = symbolData["identifier"] as? [String: Any],
                  let precise = identifier["precise"] as? String,
                  let kind = symbolData["kind"] as? [String: Any],
                  let kindIdentifier = kind["identifier"] as? String,
                  let names = symbolData["names"] as? [String: Any],
                  let title = names["title"] as? String else {
                continue
            }

            let accessLevel: AccessLevel
            if let access = symbolData["accessLevel"] as? String {
                accessLevel = AccessLevel(fromSymbolGraph: access)
            } else {
                accessLevel = .internal
            }

            let declaration = extractDeclaration(from: symbolData)
            let documentation = extractDocumentation(from: symbolData)
            let location = extractLocation(from: symbolData)
            let parameters = extractParameters(from: symbolData)
            let returnType = extractReturnType(from: symbolData)

            let fullyQualified = precise.contains("::") ? precise : "\(moduleName).\(title)"

            let symbol = Symbol(
                name: title,
                kind: SymbolKind(fromSymbolGraph: kindIdentifier),
                moduleName: moduleName,
                fullyQualifiedName: fullyQualified,
                declaration: declaration,
                documentation: documentation,
                filePath: location?.path,
                line: location?.line,
                accessLevel: accessLevel,
                parameters: parameters,
                returnType: returnType
            )
            symbols.append(symbol)
        }

        return symbols
    }

    private func extractDeclaration(from symbolData: [String: Any]) -> String? {
        guard let declarationFragments = symbolData["declarationFragments"] as? [[String: Any]] else {
            return nil
        }
        return declarationFragments.compactMap { $0["spelling"] as? String }.joined()
    }

    private func extractDocumentation(from symbolData: [String: Any]) -> String? {
        guard let docComment = symbolData["docComment"] as? [String: Any],
              let lines = docComment["lines"] as? [[String: Any]] else {
            return nil
        }
        return lines.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    private func extractLocation(from symbolData: [String: Any]) -> (path: String, line: Int)? {
        guard let location = symbolData["location"] as? [String: Any],
              let uri = location["uri"] as? String,
              let position = location["position"] as? [String: Any],
              let line = position["line"] as? Int else {
            return nil
        }
        let path = uri.hasPrefix("file://") ? String(uri.dropFirst(7)) : uri
        return (path, line)
    }

    private func extractParameters(from symbolData: [String: Any]) -> [Symbol.Parameter]? {
        guard let functionSignature = symbolData["functionSignature"] as? [String: Any],
              let parameters = functionSignature["parameters"] as? [[String: Any]] else {
            return nil
        }

        return parameters.compactMap { param -> Symbol.Parameter? in
            guard let name = param["name"] as? String else { return nil }

            var typeString: String?
            if let declarationFragments = param["declarationFragments"] as? [[String: Any]] {
                typeString = declarationFragments.compactMap { $0["spelling"] as? String }.joined()
            }

            return Symbol.Parameter(
                name: name,
                type: typeString ?? "Unknown",
                documentation: nil
            )
        }
    }

    private func extractReturnType(from symbolData: [String: Any]) -> String? {
        guard let functionSignature = symbolData["functionSignature"] as? [String: Any],
              let returns = functionSignature["returns"] as? [[String: Any]] else {
            return nil
        }
        return returns.compactMap { $0["spelling"] as? String }.joined()
    }
}

enum SymbolGraphError: Error, LocalizedError {
    case extractionFailed(String)
    case buildFailed(String)
    case sdkNotFound
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let message):
            return "Symbol graph extraction failed: \(message)"
        case .buildFailed(let message):
            return "Package build failed: \(message)"
        case .sdkNotFound:
            return "Could not find macOS SDK path"
        case .parseError(let message):
            return "Failed to parse symbol graph: \(message)"
        }
    }
}
