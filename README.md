# AppleDocsTool

An MCP (Model Context Protocol) server that provides Claude Code with access to Swift project symbols and Apple's official documentation.

## Features

- **Project Symbol Extraction** - Parse Swift Package Manager and Xcode projects to extract types, functions, and documentation
- **Apple Documentation Lookup** - Fetch up-to-date documentation from Apple's developer portal
- **Local Documentation Fallback** - Use locally installed Xcode documentation when available
- **Unified Search** - Search across your project symbols and Apple frameworks simultaneously

## Requirements

- macOS 13.0+
- Swift 6.0+ (Xcode 16+)
- Claude Code CLI

## Installation

### Build from Source

```bash
git clone https://github.com/yourusername/AppleDocsTool.git
cd AppleDocsTool
swift build -c release
```

The executable will be at `.build/release/AppleDocsTool`.

### Configure Claude Code

Add the MCP server to Claude Code:

```bash
claude mcp add apple-docs /path/to/AppleDocsTool/.build/release/AppleDocsTool
```

Or manually add to your MCP configuration (`~/.claude.json` or project `.claude/settings.json`):

```json
{
  "mcpServers": {
    "apple-docs": {
      "command": "/path/to/AppleDocsTool/.build/release/AppleDocsTool",
      "args": []
    }
  }
}
```

## Available Tools

### `get_project_symbols`

Extract all symbols from a Swift project.

**Parameters:**
- `project_path` (required): Path to Package.swift, .xcodeproj, or .xcworkspace
- `target` (optional): Specific target to analyze
- `minimum_access_level` (optional): "public", "internal", or "private" (default: "public")

**Example:**
```
Get all public symbols from my project at /Users/me/MyApp
```

### `get_symbol_documentation`

Get detailed documentation for a specific symbol.

**Parameters:**
- `project_path` (required): Path to the Swift project
- `symbol_name` (required): Fully qualified symbol name (e.g., "MyModule.MyClass.myMethod")

**Example:**
```
Get documentation for the AppDelegate class in /Users/me/MyApp
```

### `lookup_apple_api`

Fetch Apple's official documentation for system frameworks.

**Parameters:**
- `framework` (required): Framework name (e.g., "SwiftUI", "Foundation", "UIKit")
- `symbol` (optional): Specific symbol to look up
- `use_local` (optional): Prefer local Xcode docs (default: true)

**Example:**
```
Look up the SwiftUI View protocol
Look up Foundation's URLSession documentation
```

### `search_symbols`

Search across project symbols and Apple frameworks.

**Parameters:**
- `query` (required): Search query
- `project_path` (optional): Path to Swift project to include
- `frameworks` (optional): Apple frameworks to search (default: Foundation, SwiftUI, UIKit, Combine)

**Example:**
```
Search for "Button" in SwiftUI and my project at /Users/me/MyApp
```

## How It Works

### Symbol Extraction

AppleDocsTool uses Swift's built-in `swift symbolgraph-extract` tool to generate structured symbol information from compiled Swift modules. This provides accurate type information, function signatures, and documentation comments.

### Apple Documentation

Documentation is fetched from Apple's public JSON API at `developer.apple.com/tutorials/data/documentation/`. This ensures you always get the latest documentation for Apple frameworks.

When local Xcode documentation is available, AppleDocsTool can also parse `.swiftinterface` files from the macOS SDK for offline access.

## Supported Project Types

- **Swift Package Manager** - Projects with `Package.swift`
- **Xcode Projects** - `.xcodeproj` bundles
- **Xcode Workspaces** - `.xcworkspace` bundles

## Troubleshooting

### "No symbols found"

- Ensure the project builds successfully (`swift build` or Xcode build)
- For SPM packages, symbols are extracted from built modules in `.build/`
- Check that symbols meet the minimum access level (default: public)

### "Framework not found"

- Verify the framework name matches Apple's naming (case-sensitive)
- Common frameworks: SwiftUI, Foundation, UIKit, AppKit, Combine, CoreData

### Connection Issues

- Ensure the MCP server path is correct in your configuration
- Check that the executable has execute permissions: `chmod +x AppleDocsTool`
- View Claude Code logs for connection errors

## Development

### Project Structure

```
AppleDocsTool/
├── Package.swift
└── Sources/AppleDocsTool/
    ├── main.swift                 # Entry point
    ├── Server/
    │   └── MCPServer.swift        # MCP server & tool handlers
    ├── Models/
    │   ├── Symbol.swift           # Swift symbol representation
    │   ├── Documentation.swift    # Apple docs models
    │   └── Project.swift          # Project configuration
    └── Services/
        ├── SymbolGraphService.swift   # swift-symbolgraph-extract wrapper
        ├── SPMParser.swift            # Package.swift parser
        ├── XcodeProjectParser.swift   # .xcodeproj parser
        ├── AppleDocsService.swift     # Apple web docs fetcher
        └── LocalDocsService.swift     # Local Xcode docs reader
```

### Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run tests
swift test
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) - Official Model Context Protocol SDK for Swift
- [Apple Developer Documentation](https://developer.apple.com/documentation/) - Source for framework documentation
