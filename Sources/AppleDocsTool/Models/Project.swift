import Foundation

/// Represents a Swift project (SPM or Xcode)
struct Project: Sendable {
    let path: String
    let type: ProjectType
    let name: String
    let targets: [Target]

    struct Target: Sendable {
        let name: String
        let moduleName: String
        let sourcePaths: [String]
        let dependencies: [String]
    }
}

enum ProjectType: String, Sendable {
    case spm = "Swift Package"
    case xcode = "Xcode Project"
    case xcworkspace = "Xcode Workspace"
}

/// Result from parsing Package.swift
struct SPMManifest: Codable, Sendable {
    let name: String
    let targets: [SPMTarget]

    struct SPMTarget: Codable, Sendable {
        let name: String
        let type: String
        let path: String?
        let sources: [String]?
        let dependencies: [SPMDependency]?

        struct SPMDependency: Codable, Sendable {
            let target: [String]?
            let product: [String]?
        }
    }
}

/// Simplified Xcode project structure
struct XcodeProject: Sendable {
    let name: String
    let targets: [XcodeTarget]

    struct XcodeTarget: Sendable {
        let name: String
        let productName: String?
        let sourceBuildPhase: [String]
    }
}
