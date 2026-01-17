# Lookup Documentation

Find documentation for Apple frameworks, Swift APIs, and third-party dependencies.

## When to Use

- Need to understand how an Apple API works
- Looking for method signatures and parameters
- Checking availability (iOS version requirements)
- Finding documentation for dependencies

## Apple Framework Documentation

### Quick Web Lookup

Apple's documentation is well-indexed. Construct URLs directly:

```bash
# Pattern: https://developer.apple.com/documentation/{framework}/{symbol}

# Examples:
# SwiftUI View: https://developer.apple.com/documentation/swiftui/view
# UIKit UIViewController: https://developer.apple.com/documentation/uikit/uiviewcontroller
# Foundation URL: https://developer.apple.com/documentation/foundation/url
```

### Using `swift-doc` Comments

Check if the codebase has inline documentation:

```bash
# Find documented symbols
grep -rn "/// " Sources/ | head -20

# Find symbols with full doc comments
grep -B5 -A10 "/// -" Sources/
```

### Local Xcode Documentation

```bash
# Xcode docs location
ls ~/Library/Developer/Xcode/DocumentationCache/

# Search local docs (if downloaded)
find ~/Library/Developer -name "*.doccarchive" 2>/dev/null
```

## Dependency Documentation

### GitHub README

Most Swift packages have documentation in their README:

```bash
# Get repo URL from Package.resolved
cat Package.resolved | jq -r '.pins[] | "\(.identity): \(.location)"'

# Then fetch the README (example with curl)
# curl -s https://raw.githubusercontent.com/owner/repo/main/README.md
```

### Common Documentation Locations

| Package | Documentation |
|---------|--------------|
| Alamofire | https://github.com/Alamofire/Alamofire |
| SwiftyJSON | https://github.com/SwiftyJSON/SwiftyJSON |
| Kingfisher | https://github.com/onevcat/Kingfisher |
| SnapKit | https://github.com/SnapKit/SnapKit |
| Vapor | https://docs.vapor.codes |

### From Package.swift

```bash
# Find dependencies and their sources
grep -A2 ".package(" Package.swift
```

## Swift Standard Library

### Common Types

```
# String: https://developer.apple.com/documentation/swift/string
# Array: https://developer.apple.com/documentation/swift/array
# Dictionary: https://developer.apple.com/documentation/swift/dictionary
# Optional: https://developer.apple.com/documentation/swift/optional
# Result: https://developer.apple.com/documentation/swift/result
```

### Protocol Reference

```
# Codable: https://developer.apple.com/documentation/swift/codable
# Hashable: https://developer.apple.com/documentation/swift/hashable
# Equatable: https://developer.apple.com/documentation/swift/equatable
# Comparable: https://developer.apple.com/documentation/swift/comparable
# Identifiable: https://developer.apple.com/documentation/swift/identifiable
```

## Search Strategies

### Find How Something Is Used

```bash
# Find usage examples in the codebase
grep -rn "URLSession" Sources/

# Find imports
grep -rn "^import " Sources/ | sort -u
```

### Check Availability

```bash
# Find availability annotations
grep -rn "@available" Sources/

# Common pattern
grep -rn "if #available" Sources/
```

## Quick Reference: Common APIs

### Async/Await
```swift
// Task, async, await - Swift 5.5+
// https://developer.apple.com/documentation/swift/task
```

### Combine
```swift
// Publisher, Subscriber, Subject
// https://developer.apple.com/documentation/combine
```

### SwiftUI
```swift
// View, @State, @Binding, @ObservedObject
// https://developer.apple.com/documentation/swiftui
```

## Tips

- Apple's documentation URLs are predictable: `/documentation/{framework}/{symbol}`
- GitHub READMEs are usually the best starting point for dependencies
- Check `Package.resolved` for exact versions being used
- Search the codebase for usage examples - often more helpful than docs

## MCP Fallback

For programmatic access or when web lookup isn't sufficient:
- `lookup_apple_api` - Fetches structured Apple documentation
- `get_dependency_docs` - Fetches README from GitHub
- `search_symbols` - Searches local and Apple symbols together
