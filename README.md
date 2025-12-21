# AppleDocsTool

An MCP (Model Context Protocol) server that provides Claude Code with access to Swift project symbols and Apple's official documentation.

## Features

- **Project Symbol Extraction** - Parse Swift Package Manager and Xcode projects to extract types, functions, and documentation
- **Dependency Awareness** - Extract symbols from all package dependencies so Claude knows what's already available (prevents code duplication!)
- **GitHub Documentation** - Fetch README and documentation from dependency GitHub repositories
- **Apple Documentation Lookup** - Fetch up-to-date documentation from Apple's developer portal
- **Local Documentation Fallback** - Use locally installed Xcode documentation when available
- **Fuzzy Search** - Search across project symbols and Apple frameworks with intelligent matching (exact, prefix, camelCase, fuzzy)
- **Project Summary** - Quick overview of project structure, dependencies, and key types

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

## Using with Claude Code

### Quick Start

Once configured, start Claude Code in your Swift project directory:

```bash
cd ~/Developer/MySwiftApp
claude
```

Claude will automatically have access to the AppleDocsTool MCP server.

### Example Prompts

**Get oriented in a new project:**
```
Give me an overview of this project
```
→ Uses `get_project_summary` to show targets, dependencies, and key types

**Understand dependencies before coding:**
```
What dependencies does this project have? Show me their APIs
```
→ Uses `get_project_dependencies` with `include_symbols: true`

**Look up Apple framework documentation:**
```
How do I use SwiftUI's Chart view?
```
→ Uses `lookup_apple_api` with framework: "Charts", symbol: "Chart"

**Search across everything:**
```
Find all ViewModels in this project
```
→ Uses `search_symbols` with query: "ViewModel"

**Get library documentation:**
```
Show me how to use Alamofire
```
→ Uses `get_dependency_docs` to fetch the README from GitHub

### Project-Specific Configuration

For per-project settings, create `.claude/settings.json` in your project root:

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

### Verify Installation

Check that the MCP server is registered:

```bash
claude mcp list
```

You should see `apple-docs` in the list.

### Tips for Best Results

1. **Build your project first** - Symbol extraction requires compiled modules
   - SPM: `swift build`
   - Xcode: Build in Xcode (Cmd+B)

2. **Use `get_project_summary` first** - When starting on unfamiliar code, this gives Claude context about the project structure

3. **Include dependencies** - Use `include_dependencies: true` to help Claude understand what libraries are available

4. **Be specific with Apple docs** - Use symbol names like "Chart" or "URLSession", not article titles

## Available Tools

### `get_project_symbols`

Extract all symbols from a Swift project, optionally including dependency symbols.

**Parameters:**
- `project_path` (required): Path to Package.swift, .xcodeproj, or .xcworkspace
- `target` (optional): Specific target to analyze
- `minimum_access_level` (optional): "public", "internal", or "private" (default: "public")
- `include_dependencies` (optional): Include symbols from all package dependencies (default: false)

**Example:**
```
Get all public symbols from my project at /Users/me/MyApp, including dependencies
```

### `get_project_dependencies`

List all dependencies for a Swift package with versions and optionally extract their symbols.

**Parameters:**
- `project_path` (required): Path to Package.swift or directory containing it
- `include_symbols` (optional): Extract public symbols from each dependency (default: false)

**Example:**
```
What dependencies does my project at /Users/me/MyApp have?
Show me all the APIs available from my project's dependencies
```

**Why This Matters:** When Claude knows what's in your dependencies, it won't accidentally reimplement functionality that already exists. For example, if you have Alamofire as a dependency, Claude will use it instead of writing custom networking code.

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

Search across project symbols and Apple frameworks with fuzzy matching and relevance ranking.

**Parameters:**
- `query` (required): Search query - supports exact names, prefixes, camelCase (e.g., "VM" finds "ViewModel"), and fuzzy matching
- `project_path` (optional): Path to Swift project to include
- `frameworks` (optional): Apple frameworks to search (default: Foundation, SwiftUI, UIKit, Combine)
- `max_results` (optional): Maximum results to return (default: 50)

**Match Types (in priority order):**
- `exact` - Perfect match
- `prefix` - Query matches start of symbol name
- `camelCase` - Query matches capital letters (e.g., "NSO" finds "NSObject")
- `contains` - Query found within symbol name
- `wordBoundary` - Query matches word start
- `fuzzy` - Similar spelling (Levenshtein distance)
- `subsequence` - All query characters appear in order

**Example:**
```
Search for "Button" in SwiftUI and my project at /Users/me/MyApp
Search for "VM" to find all ViewModels
```

### `get_dependency_docs`

Fetch README and documentation from a dependency's GitHub repository. Use this to understand how to use a third-party library.

**Parameters:**
- `github_url` (optional): Direct GitHub URL to the repository
- `project_path` (optional): Path to Swift project (to look up dependency URLs)
- `dependency_name` (optional): Name of the dependency to look up

**Example:**
```
Get the documentation for Alamofire from my project's dependencies
Fetch the README from https://github.com/Alamofire/Alamofire
```

### `get_project_summary`

Get a quick overview of a Swift project including targets, dependencies, and key public types. **Use this first when starting work on an unfamiliar project.**

**Parameters:**
- `project_path` (required): Path to Package.swift, .xcodeproj, or directory

**Example:**
```
Give me an overview of the project at /Users/me/MyApp
```

**Output includes:**
- Project name and type
- All targets with their dependencies
- External dependencies with versions
- Key public types (structs, classes, protocols, enums)

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
    │   └── MCPServer.swift        # MCP server & tool handlers (7 tools)
    ├── Models/
    │   ├── Symbol.swift           # Swift symbol representation
    │   ├── Documentation.swift    # Apple docs models
    │   └── Project.swift          # Project configuration
    └── Services/
        ├── SymbolGraphService.swift   # swift-symbolgraph-extract wrapper
        ├── DependencyService.swift    # Package dependency analysis
        ├── GitHubDocsService.swift    # GitHub README/docs fetcher
        ├── SearchService.swift        # Fuzzy search & ranking
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
