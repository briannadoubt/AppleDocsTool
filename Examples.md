# AppleDocsTool Examples

Real-world examples of using AppleDocsTool with Claude Code.

## Looking Up Apple Documentation

### Get SwiftUI Framework Overview

```
You: What's in the SwiftUI framework?

Claude: [uses lookup_apple_api with framework="SwiftUI"]

SwiftUI is Apple's declarative UI framework introduced in iOS 13...
```

### Look Up a Specific Symbol

```
You: Show me the documentation for SwiftUI's View protocol

Claude: [uses lookup_apple_api with framework="SwiftUI", symbol="View"]

The View protocol is the foundation of SwiftUI...
- Required: var body: some View { get }
- Available on iOS 13.0+, macOS 10.15+...
```

### Explore Foundation APIs

```
You: How do I use URLSession to make network requests?

Claude: [uses lookup_apple_api with framework="Foundation", symbol="URLSession"]

URLSession provides an API for downloading and uploading data...
```

## Analyzing Your Swift Projects

### Extract Project Symbols

```
You: What public types are in my project at ~/Developer/MyApp?

Claude: [uses get_project_symbols with project_path="~/Developer/MyApp"]

Found 47 public symbols in MyApp:
- struct ContentView: View
- class NetworkManager
- enum AppError
- func fetchData() async throws -> Data
...
```

### Get Symbol Details

```
You: Show me the documentation for NetworkManager in my project

Claude: [uses get_symbol_documentation with project_path="~/Developer/MyApp", symbol_name="MyApp.NetworkManager"]

/// Handles all network communication for the app
///
/// Use this class to make API requests:
/// ```swift
/// let manager = NetworkManager()
/// let data = try await manager.fetch(from: url)
/// ```
class NetworkManager {
    func fetch(from url: URL) async throws -> Data
    ...
}
```

### Analyze Internal APIs

```
You: Show me all internal types in my app (not just public)

Claude: [uses get_project_symbols with project_path="~/Developer/MyApp", minimum_access_level="internal"]

Found 156 symbols (including internal):
- internal struct CacheEntry
- internal class DatabaseManager
- private func validateInput(_ input: String) -> Bool
...
```

## Searching Across Everything

### Fuzzy Search with Ranking

```
You: Search for anything related to "Button" in my project and SwiftUI

Claude: [uses search_symbols with query="Button", project_path="~/Developer/MyApp", frameworks=["SwiftUI"]]

Found 15 matching symbols (3 exact, 5 prefix, 4 contains, 3 fuzzy):

From your project (score 1.0 - exact match):
- struct Button: View (Sources/Components/Button.swift)

From SwiftUI (score 0.95 - prefix):
- struct ButtonStyle
- struct ButtonStyleConfiguration

From project (score 0.7 - contains):
- CustomButtonView
- PrimaryButtonStyle
...
```

### CamelCase Search

```
You: Find all ViewModels using "VM"

Claude: [uses search_symbols with query="VM", project_path="~/Developer/MyApp"]

Found 8 matching symbols (8 camelCase):
- HomeViewModel (score 0.85)
- UserProfileViewModel (score 0.85)
- SettingsViewModel (score 0.85)
...
```

### Find Similar Patterns

```
You: Find all async functions in my codebase

Claude: [uses search_symbols with query="async", project_path="~/Developer/MyApp"]

Found 23 async functions:
- fetchUser() async throws -> User
- loadImages() async -> [Image]
- syncData() async
...
```

## Xcode Project Support

### Analyze Xcode Projects

```
You: What targets are in my Xcode project at ~/Developer/MyiOSApp.xcodeproj?

Claude: [uses get_project_symbols with project_path="~/Developer/MyiOSApp.xcodeproj"]

Found targets:
- MyiOSApp (iOS app)
- MyiOSAppTests (test target)
- MyiOSAppUITests (UI test target)

Symbols from MyiOSApp:
- AppDelegate
- SceneDelegate
- ContentView
...
```

### Analyze Workspaces

```
You: Analyze my workspace that includes multiple projects

Claude: [uses get_project_symbols with project_path="~/Developer/MyWorkspace.xcworkspace"]

Found projects in workspace:
- MainApp (43 symbols)
- NetworkingKit (28 symbols)
- UIComponents (67 symbols)
...
```

## Understanding Dependencies

### Get Project Overview

```
You: Give me an overview of this project at ~/Developer/MyApp

Claude: [uses get_project_summary with project_path="~/Developer/MyApp"]

# Project Summary

**Name:** MyApp
**Type:** Swift Package

## Targets (3)
- MyApp (module: MyApp)
- MyAppTests (dependencies: MyApp)
- MyAppCLI (dependencies: MyApp)

## External Dependencies (4)
- Alamofire (v5.8.1)
- swift-argument-parser (v1.3.0)
- KeychainAccess (v4.2.2)
- SwiftLint (v0.54.0)

## Key Types
- Structs: 12 (AppConfig, User, AuthToken, ...)
- Classes: 5 (NetworkManager, DatabaseService, ...)
- Protocols: 8 (APIEndpoint, Cacheable, ...)
- Enums: 6 (AppError, NetworkState, ...)
```

### Fetch Dependency Documentation

```
You: How do I use Alamofire? Get me its documentation.

Claude: [uses get_dependency_docs with project_path="~/Developer/MyApp", dependency_name="Alamofire"]

# Alamofire

**Description:** Elegant HTTP Networking in Swift
**URL:** https://github.com/Alamofire/Alamofire
**Stars:** 40,234
**License:** MIT License
**Topics:** swift, networking, http, urlsession

---

## README

Alamofire is an HTTP networking library written in Swift.

### Features
- Chainable Request / Response Methods
- Swift Concurrency Support
- URL / JSON Parameter Encoding
...
```

### Get Docs from GitHub URL

```
You: Show me the documentation for https://github.com/kishikawakatsumi/KeychainAccess

Claude: [uses get_dependency_docs with github_url="https://github.com/kishikawakatsumi/KeychainAccess"]

# KeychainAccess

**Description:** Simple Swift wrapper for Keychain...
...
```

## Tips for Best Results

1. **Start with get_project_summary** - When working on an unfamiliar project, use this first to understand the structure

2. **Check dependencies before implementing** - Use get_project_dependencies to see what libraries are already available

3. **Use get_dependency_docs for library usage** - When you need to use a dependency, fetch its README to understand the API

4. **Be specific with symbol names** - Use fully qualified names like `MyModule.MyClass.myMethod`

5. **Build your project first** - Symbol extraction works best after a successful build

6. **Use appropriate access levels** - Default is `public`; use `internal` to see more

7. **Framework names are case-sensitive** - Use `SwiftUI` not `swiftui`

8. **Use fuzzy search for exploration** - Search with partial names or camelCase abbreviations like "VM" for ViewModel
