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

### Search Project + Apple Frameworks

```
You: Search for anything related to "Button" in my project and SwiftUI

Claude: [uses search_symbols with query="Button", project_path="~/Developer/MyApp", frameworks=["SwiftUI"]]

Found 12 matching symbols:

From your project:
- CustomButton: View (Sources/Components/CustomButton.swift)
- ButtonStyle (Sources/Styles/ButtonStyles.swift)

From SwiftUI:
- struct Button<Label>: View
- protocol ButtonStyle
- struct BorderedButtonStyle
- struct PlainButtonStyle
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

## Tips for Best Results

1. **Be specific with symbol names** - Use fully qualified names like `MyModule.MyClass.myMethod`

2. **Build your project first** - Symbol extraction works best after a successful build

3. **Use appropriate access levels** - Default is `public`; use `internal` to see more

4. **Framework names are case-sensitive** - Use `SwiftUI` not `swiftui`

5. **Combine tools** - Search first, then get detailed docs for what you find
