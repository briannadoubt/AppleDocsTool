import Foundation

/// Parser for Xcode projects (.xcodeproj and .xcworkspace)
actor XcodeProjectParser {
    private let fileManager = FileManager.default

    /// Parse an Xcode project or workspace
    func parseProject(at path: String) async throws -> Project {
        if path.hasSuffix(".xcworkspace") {
            return try await parseWorkspace(at: path)
        } else if path.hasSuffix(".xcodeproj") {
            return try await parseXcodeProject(at: path)
        } else {
            // Try to find project in directory
            let contents = try fileManager.contentsOfDirectory(atPath: path)

            if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
                return try await parseWorkspace(at: "\(path)/\(workspace)")
            } else if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
                return try await parseXcodeProject(at: "\(path)/\(project)")
            }

            throw XcodeParserError.projectNotFound(path)
        }
    }

    private func parseWorkspace(at path: String) async throws -> Project {
        let contentsPath = "\(path)/contents.xcworkspacedata"

        guard fileManager.fileExists(atPath: contentsPath) else {
            throw XcodeParserError.invalidWorkspace(path)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: contentsPath))
        let xml = String(data: data, encoding: .utf8) ?? ""

        // Parse workspace to find project references
        let projectPaths = parseWorkspaceXML(xml, basePath: (path as NSString).deletingLastPathComponent)

        var allTargets: [Project.Target] = []
        let workspaceName = (path as NSString).lastPathComponent.replacingOccurrences(of: ".xcworkspace", with: "")

        for projectPath in projectPaths {
            if let project = try? await parseXcodeProject(at: projectPath) {
                allTargets.append(contentsOf: project.targets)
            }
        }

        return Project(
            path: (path as NSString).deletingLastPathComponent,
            type: .xcworkspace,
            name: workspaceName,
            targets: allTargets
        )
    }

    private func parseWorkspaceXML(_ xml: String, basePath: String) -> [String] {
        var projectPaths: [String] = []

        // Simple XML parsing for FileRef elements
        let pattern = #"location\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return projectPaths
        }

        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, range: range)

        for match in matches {
            if let range = Range(match.range(at: 1), in: xml) {
                var location = String(xml[range])

                // Handle different location types
                if location.hasPrefix("group:") {
                    location = String(location.dropFirst(6))
                    location = "\(basePath)/\(location)"
                } else if location.hasPrefix("absolute:") {
                    location = String(location.dropFirst(9))
                } else if location.hasPrefix("container:") {
                    location = String(location.dropFirst(10))
                    location = "\(basePath)/\(location)"
                }

                if location.hasSuffix(".xcodeproj") {
                    projectPaths.append(location)
                }
            }
        }

        return projectPaths
    }

    private func parseXcodeProject(at path: String) async throws -> Project {
        let pbxprojPath = "\(path)/project.pbxproj"

        guard fileManager.fileExists(atPath: pbxprojPath) else {
            throw XcodeParserError.invalidProject(path)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: pbxprojPath))
        guard let content = String(data: data, encoding: .utf8) else {
            throw XcodeParserError.invalidProject(path)
        }

        let projectName = (path as NSString).lastPathComponent.replacingOccurrences(of: ".xcodeproj", with: "")
        let projectDir = (path as NSString).deletingLastPathComponent
        let targets = parseTargets(from: content, projectDir: projectDir)

        return Project(
            path: projectDir,
            type: .xcode,
            name: projectName,
            targets: targets
        )
    }

    private func parseTargets(from pbxproj: String, projectDir: String) -> [Project.Target] {
        var targets: [Project.Target] = []

        // Parse native targets
        let targetPattern = #"/\* Begin PBXNativeTarget section \*/\s*([\s\S]*?)\s*/\* End PBXNativeTarget section \*/"#
        guard let targetRegex = try? NSRegularExpression(pattern: targetPattern),
              let targetMatch = targetRegex.firstMatch(in: pbxproj, range: NSRange(pbxproj.startIndex..., in: pbxproj)),
              let targetRange = Range(targetMatch.range(at: 1), in: pbxproj) else {
            return targets
        }

        let targetSection = String(pbxproj[targetRange])

        // Extract individual targets
        let individualTargetPattern = #"([A-F0-9]+)\s*/\*\s*([^*]+)\s*\*/\s*=\s*\{[^}]*name\s*=\s*"?([^";]+)"?[^}]*productName\s*=\s*"?([^";]+)"?"#
        guard let individualRegex = try? NSRegularExpression(pattern: individualTargetPattern) else {
            return targets
        }

        let matches = individualRegex.matches(in: targetSection, range: NSRange(targetSection.startIndex..., in: targetSection))

        for match in matches {
            guard let nameRange = Range(match.range(at: 3), in: targetSection) else { continue }
            let targetName = String(targetSection[nameRange]).trimmingCharacters(in: .whitespaces)

            let productName: String?
            if let productRange = Range(match.range(at: 4), in: targetSection) {
                productName = String(targetSection[productRange]).trimmingCharacters(in: .whitespaces)
            } else {
                productName = targetName
            }

            targets.append(Project.Target(
                name: targetName,
                moduleName: productName ?? targetName,
                sourcePaths: [projectDir],
                dependencies: []
            ))
        }

        // Fallback: try simpler parsing if no targets found
        if targets.isEmpty {
            let simplePattern = #"name\s*=\s*"([^"]+)";\s*productName"#
            if let simpleRegex = try? NSRegularExpression(pattern: simplePattern) {
                let matches = simpleRegex.matches(in: pbxproj, range: NSRange(pbxproj.startIndex..., in: pbxproj))
                for match in matches {
                    if let nameRange = Range(match.range(at: 1), in: pbxproj) {
                        let name = String(pbxproj[nameRange])
                        if !targets.contains(where: { $0.name == name }) {
                            targets.append(Project.Target(
                                name: name,
                                moduleName: name,
                                sourcePaths: [projectDir],
                                dependencies: []
                            ))
                        }
                    }
                }
            }
        }

        return targets
    }

    /// Get all target names from a project
    func getTargetNames(at path: String) async throws -> [String] {
        let project = try await parseProject(at: path)
        return project.targets.map { $0.name }
    }
}

enum XcodeParserError: Error, LocalizedError {
    case projectNotFound(String)
    case invalidProject(String)
    case invalidWorkspace(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let path):
            return "No Xcode project or workspace found at: \(path)"
        case .invalidProject(let path):
            return "Invalid Xcode project at: \(path)"
        case .invalidWorkspace(let path):
            return "Invalid Xcode workspace at: \(path)"
        }
    }
}
