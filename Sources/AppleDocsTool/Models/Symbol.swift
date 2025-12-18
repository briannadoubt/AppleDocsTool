import Foundation

/// Represents a Swift symbol extracted from a project
struct Symbol: Codable, Sendable {
    let name: String
    let kind: SymbolKind
    let moduleName: String
    let fullyQualifiedName: String
    let declaration: String?
    let documentation: String?
    let filePath: String?
    let line: Int?
    let accessLevel: AccessLevel
    let parameters: [Parameter]?
    let returnType: String?

    struct Parameter: Codable, Sendable {
        let name: String
        let type: String
        let documentation: String?
    }
}

enum SymbolKind: String, Codable, Sendable {
    case `struct`
    case `class`
    case `enum`
    case `protocol`
    case `func`
    case `var`
    case `let`
    case `typealias`
    case `init`
    case `deinit`
    case `subscript`
    case `operator`
    case `associatedtype`
    case `extension`
    case `case`
    case `actor`
    case `macro`
    case unknown

    init(fromSymbolGraph kind: String) {
        switch kind {
        case "swift.struct": self = .struct
        case "swift.class": self = .class
        case "swift.enum": self = .enum
        case "swift.protocol": self = .protocol
        case "swift.func", "swift.method", "swift.type.method", "swift.func.op": self = .func
        case "swift.var", "swift.property", "swift.type.property": self = .var
        case "swift.typealias": self = .typealias
        case "swift.init": self = .`init`
        case "swift.deinit": self = .deinit
        case "swift.subscript", "swift.type.subscript": self = .subscript
        case "swift.associatedtype": self = .associatedtype
        case "swift.enum.case": self = .case
        case "swift.actor": self = .actor
        case "swift.macro": self = .macro
        default: self = .unknown
        }
    }
}

enum AccessLevel: String, Codable, Sendable, Comparable {
    case `private`
    case `fileprivate`
    case `internal`
    case `package`
    case `public`
    case `open`

    static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
        let order: [AccessLevel] = [.private, .fileprivate, .internal, .package, .public, .open]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }

    init(fromSymbolGraph accessLevel: String) {
        switch accessLevel {
        case "private": self = .private
        case "fileprivate": self = .fileprivate
        case "internal": self = .internal
        case "package": self = .package
        case "public": self = .public
        case "open": self = .open
        default: self = .internal
        }
    }
}
