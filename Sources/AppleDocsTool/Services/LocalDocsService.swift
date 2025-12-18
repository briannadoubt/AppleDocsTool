import Foundation

/// Service for reading local Xcode documentation
actor LocalDocsService {
    private let fileManager = FileManager.default

    /// Common paths where Xcode documentation might be stored
    private let possibleDocPaths = [
        "/Applications/Xcode.app/Contents/Developer/Documentation/DocSets",
        "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks",
        "~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/share/doc"
    ]

    /// Check if local documentation is available
    func isAvailable() async -> Bool {
        for path in possibleDocPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if fileManager.fileExists(atPath: expandedPath) {
                return true
            }
        }
        return false
    }

    /// Get documentation from local Swift interface files
    func getSwiftInterfaceDocumentation(framework: String) async throws -> [Symbol] {
        let sdkPath = try await getSDKPath()
        let frameworksPath = "\(sdkPath)/System/Library/Frameworks"
        let frameworkPath = "\(frameworksPath)/\(framework).framework"

        guard fileManager.fileExists(atPath: frameworkPath) else {
            throw LocalDocsError.frameworkNotFound(framework)
        }

        // Look for .swiftinterface files
        let modulesPath = "\(frameworkPath)/Modules/\(framework).swiftmodule"

        guard fileManager.fileExists(atPath: modulesPath) else {
            throw LocalDocsError.moduleNotFound(framework)
        }

        let contents = try fileManager.contentsOfDirectory(atPath: modulesPath)
        let interfaceFiles = contents.filter { $0.hasSuffix(".swiftinterface") }

        var symbols: [Symbol] = []

        for interfaceFile in interfaceFiles {
            let filePath = "\(modulesPath)/\(interfaceFile)"
            let fileSymbols = try await parseSwiftInterface(at: filePath, moduleName: framework)
            symbols.append(contentsOf: fileSymbols)
        }

        return symbols
    }

    /// Parse a .swiftinterface file to extract public API symbols
    private func parseSwiftInterface(at path: String, moduleName: String) async throws -> [Symbol] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var symbols: [Symbol] = []
        let lines = content.components(separatedBy: .newlines)

        var currentDocComment: [String] = []
        var lineNumber = 0

        for line in lines {
            lineNumber += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Collect doc comments
            if trimmed.hasPrefix("///") {
                currentDocComment.append(String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces))
                continue
            }

            // Skip non-declaration lines
            guard !trimmed.isEmpty && !trimmed.hasPrefix("//") && !trimmed.hasPrefix("@") else {
                if !trimmed.hasPrefix("@") {
                    currentDocComment.removeAll()
                }
                continue
            }

            // Parse declarations
            if let symbol = parseDeclaration(trimmed, moduleName: moduleName, documentation: currentDocComment, filePath: path, line: lineNumber) {
                symbols.append(symbol)
            }

            currentDocComment.removeAll()
        }

        return symbols
    }

    private func parseDeclaration(_ line: String, moduleName: String, documentation: [String], filePath: String, line lineNumber: Int) -> Symbol? {
        let doc = documentation.isEmpty ? nil : documentation.joined(separator: "\n")

        // Struct
        if line.hasPrefix("public struct ") || line.hasPrefix("struct ") {
            let name = extractName(from: line, after: "struct ")
            return Symbol(
                name: name,
                kind: .struct,
                moduleName: moduleName,
                fullyQualifiedName: "\(moduleName).\(name)",
                declaration: line,
                documentation: doc,
                filePath: filePath,
                line: lineNumber,
                accessLevel: .public,
                parameters: nil,
                returnType: nil
            )
        }

        // Class
        if line.hasPrefix("public class ") || line.hasPrefix("class ") || line.hasPrefix("open class ") {
            let name = extractName(from: line, after: "class ")
            let accessLevel: AccessLevel = line.hasPrefix("open") ? .open : .public
            return Symbol(
                name: name,
                kind: .class,
                moduleName: moduleName,
                fullyQualifiedName: "\(moduleName).\(name)",
                declaration: line,
                documentation: doc,
                filePath: filePath,
                line: lineNumber,
                accessLevel: accessLevel,
                parameters: nil,
                returnType: nil
            )
        }

        // Protocol
        if line.hasPrefix("public protocol ") || line.hasPrefix("protocol ") {
            let name = extractName(from: line, after: "protocol ")
            return Symbol(
                name: name,
                kind: .protocol,
                moduleName: moduleName,
                fullyQualifiedName: "\(moduleName).\(name)",
                declaration: line,
                documentation: doc,
                filePath: filePath,
                line: lineNumber,
                accessLevel: .public,
                parameters: nil,
                returnType: nil
            )
        }

        // Enum
        if line.hasPrefix("public enum ") || line.hasPrefix("enum ") {
            let name = extractName(from: line, after: "enum ")
            return Symbol(
                name: name,
                kind: .enum,
                moduleName: moduleName,
                fullyQualifiedName: "\(moduleName).\(name)",
                declaration: line,
                documentation: doc,
                filePath: filePath,
                line: lineNumber,
                accessLevel: .public,
                parameters: nil,
                returnType: nil
            )
        }

        // Function
        if line.hasPrefix("public func ") || line.hasPrefix("func ") {
            let name = extractFunctionName(from: line)
            return Symbol(
                name: name,
                kind: .func,
                moduleName: moduleName,
                fullyQualifiedName: "\(moduleName).\(name)",
                declaration: line,
                documentation: doc,
                filePath: filePath,
                line: lineNumber,
                accessLevel: .public,
                parameters: nil,
                returnType: nil
            )
        }

        // Actor
        if line.hasPrefix("public actor ") || line.hasPrefix("actor ") {
            let name = extractName(from: line, after: "actor ")
            return Symbol(
                name: name,
                kind: .actor,
                moduleName: moduleName,
                fullyQualifiedName: "\(moduleName).\(name)",
                declaration: line,
                documentation: doc,
                filePath: filePath,
                line: lineNumber,
                accessLevel: .public,
                parameters: nil,
                returnType: nil
            )
        }

        return nil
    }

    private func extractName(from line: String, after keyword: String) -> String {
        guard let range = line.range(of: keyword) else {
            return "Unknown"
        }

        let afterKeyword = String(line[range.upperBound...])
        var name = ""

        for char in afterKeyword {
            if char.isLetter || char.isNumber || char == "_" {
                name.append(char)
            } else {
                break
            }
        }

        return name.isEmpty ? "Unknown" : name
    }

    private func extractFunctionName(from line: String) -> String {
        guard let funcRange = line.range(of: "func ") else {
            return "Unknown"
        }

        let afterFunc = String(line[funcRange.upperBound...])
        var name = ""

        for char in afterFunc {
            if char.isLetter || char.isNumber || char == "_" {
                name.append(char)
            } else {
                break
            }
        }

        return name.isEmpty ? "Unknown" : name
    }

    private func getSDKPath() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--show-sdk-path"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw LocalDocsError.sdkNotFound
        }
        return path
    }

    /// List available frameworks in the SDK
    func listAvailableFrameworks() async throws -> [String] {
        let sdkPath = try await getSDKPath()
        let frameworksPath = "\(sdkPath)/System/Library/Frameworks"

        guard fileManager.fileExists(atPath: frameworksPath) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(atPath: frameworksPath)
        return contents
            .filter { $0.hasSuffix(".framework") }
            .map { $0.replacingOccurrences(of: ".framework", with: "") }
            .sorted()
    }
}

enum LocalDocsError: Error, LocalizedError {
    case frameworkNotFound(String)
    case moduleNotFound(String)
    case sdkNotFound
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .frameworkNotFound(let name):
            return "Framework not found: \(name)"
        case .moduleNotFound(let name):
            return "Swift module not found for framework: \(name)"
        case .sdkNotFound:
            return "Could not find macOS SDK"
        case .parseError(let message):
            return "Failed to parse local documentation: \(message)"
        }
    }
}
