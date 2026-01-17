# Analyze Project

Understand the structure, dependencies, and symbols of a Swift package or Xcode project.

## When to Use

- Starting work on an unfamiliar codebase
- Need to find where something is defined
- Want to understand project dependencies
- Looking for specific symbols, types, or functions

## Quick Start

### 1. Get Project Overview

```bash
# For Swift Package Manager projects
cat Package.swift

# List all source files
find Sources -name "*.swift" | head -20

# Count lines of code
find Sources -name "*.swift" | xargs wc -l | tail -1
```

### 2. Understand Dependencies

```bash
# View resolved dependencies (SPM)
cat Package.resolved | jq '.pins[] | {package: .identity, version: .state.version}'

# Or simpler - just read it
cat Package.resolved
```

### 3. Find Symbols and Types

```bash
# Find struct/class/enum definitions
grep -rn "^struct \|^class \|^enum \|^protocol \|^actor " Sources/

# Find a specific type
grep -rn "struct MyType" Sources/

# Find function definitions
grep -rn "func " Sources/ | grep -v "^\s*//"
```

### 4. Extract Symbol Graph (Advanced)

For complete symbol information with documentation:

```bash
# Build first to ensure modules exist
swift build

# Extract symbol graph for a target
swift symbolgraph-extract \
  --module-name YourModuleName \
  --minimum-access-level public \
  --output-dir /tmp/symbols

# Read the symbols
cat /tmp/symbols/YourModuleName.symbols.json | jq '.symbols[] | {name: .names.title, kind: .kind.displayName}'
```

## Common Patterns

### Find All Public API

```bash
grep -rn "public \|open " Sources/ | grep -E "(func|var|let|class|struct|enum|protocol)"
```

### Find Protocol Conformances

```bash
grep -rn ": .*Protocol\|: Codable\|: Hashable\|: Equatable" Sources/
```

### Find TODO/FIXME Comments

```bash
grep -rn "TODO\|FIXME\|HACK\|XXX" Sources/
```

### Understand File Organization

```bash
# Show directory tree
find Sources -type f -name "*.swift" | sed 's|/[^/]*$||' | sort -u | while read dir; do
  echo "$dir/:"
  ls "$dir"/*.swift 2>/dev/null | xargs -n1 basename
done
```

## For Xcode Projects

```bash
# List schemes
xcodebuild -list

# Show build settings
xcodebuild -showBuildSettings -scheme YourScheme 2>/dev/null | grep -E "PRODUCT_NAME|BUNDLE_ID|DEPLOYMENT_TARGET"

# Find the main target's source files
find . -name "*.xcodeproj" -exec cat {}/project.pbxproj \; | grep "\.swift" | head -20
```

## Tips

- Start with `Package.swift` or the `.xcodeproj` to understand the project structure
- Use `grep -rn` to search with line numbers for easy navigation
- The symbol graph gives you the most accurate picture but requires a successful build
- For large projects, focus on the `Sources/` directory first

## MCP Fallback

If you need structured data or the shell commands aren't sufficient:
- `get_project_summary` - JSON overview of project
- `get_project_symbols` - Parsed symbol information
- `search_symbols` - Fuzzy search across symbols
