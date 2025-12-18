import Foundation

/// Represents documentation fetched from Apple's documentation system
struct AppleDocumentation: Codable, Sendable {
    let identifier: String
    let title: String
    let abstract: String?
    let declaration: String?
    let discussion: String?
    let parameters: [DocumentationParameter]?
    let returnValue: String?
    let availability: [PlatformAvailability]?
    let relatedSymbols: [RelatedSymbol]?
    let url: String?
    let framework: String

    struct DocumentationParameter: Codable, Sendable {
        let name: String
        let discussion: String?
    }

    struct PlatformAvailability: Codable, Sendable {
        let platform: String
        let introducedAt: String?
        let deprecatedAt: String?
    }

    struct RelatedSymbol: Codable, Sendable {
        let title: String
        let identifier: String
        let kind: String?
    }
}

/// Response from Apple's documentation JSON API
struct AppleDocsResponse: Codable, Sendable {
    let identifier: AppleDocsIdentifier
    let metadata: AppleDocsMetadata
    let abstract: [AppleDocsInlineContent]?
    let primaryContentSections: [AppleDocsContentSection]?
    let topicSections: [AppleDocsTopicSection]?
    let relationshipsSections: [AppleDocsRelationshipsSection]?
    let references: [String: AppleDocsReference]?

    struct AppleDocsIdentifier: Codable, Sendable {
        let url: String
        let interfaceLanguage: String
    }

    struct AppleDocsMetadata: Codable, Sendable {
        let title: String
        let role: String?
        let roleHeading: String?
        let symbolKind: String?
        let modules: [AppleDocsModule]?
        let platforms: [AppleDocsPlatform]?
        let fragments: [AppleDocsFragment]?
    }

    struct AppleDocsModule: Codable, Sendable {
        let name: String
    }

    struct AppleDocsPlatform: Codable, Sendable {
        let name: String
        let introducedAt: String?
        let beta: Bool?
    }

    struct AppleDocsFragment: Codable, Sendable {
        let kind: String
        let text: String
    }

    struct AppleDocsInlineContent: Codable, Sendable {
        let type: String
        let text: String?
        let code: String?
        let identifier: String?
    }

    struct AppleDocsContentSection: Codable, Sendable {
        let kind: String
        let declarations: [AppleDocsDeclaration]?
        let content: [AppleDocsContent]?
        let parameters: [AppleDocsParameter]?
    }

    struct AppleDocsDeclaration: Codable, Sendable {
        let platforms: [String]?
        let tokens: [AppleDocsToken]?
    }

    struct AppleDocsToken: Codable, Sendable {
        let kind: String
        let text: String
    }

    struct AppleDocsContent: Codable, Sendable {
        let type: String
        let inlineContent: [AppleDocsInlineContent]?
        let items: [AppleDocsListItem]?
        let content: [AppleDocsContent]?
    }

    struct AppleDocsListItem: Codable, Sendable {
        let content: [AppleDocsContent]?
    }

    struct AppleDocsParameter: Codable, Sendable {
        let name: String
        let content: [AppleDocsContent]?
    }

    struct AppleDocsTopicSection: Codable, Sendable {
        let title: String
        let identifiers: [String]
    }

    struct AppleDocsRelationshipsSection: Codable, Sendable {
        let kind: String
        let title: String
        let identifiers: [String]
    }

    struct AppleDocsReference: Codable, Sendable {
        let identifier: String
        let title: String?
        let url: String?
        let abstract: [AppleDocsInlineContent]?
        let kind: String?
        let role: String?
        let type: String?
        let fragments: [AppleDocsFragment]?
    }
}
