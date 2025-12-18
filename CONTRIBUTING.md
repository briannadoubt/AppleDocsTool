# Contributing to AppleDocsTool

Thanks for your interest in contributing!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/AppleDocsTool.git`
3. Create a branch: `git checkout -b feature/your-feature`
4. Make your changes
5. Build and test: `swift build && swift test`
6. Commit your changes: `git commit -m "Add your feature"`
7. Push to your fork: `git push origin feature/your-feature`
8. Open a Pull Request

## Development Setup

### Requirements

- macOS 13.0+
- Xcode 16+ (Swift 6.0)
- Claude Code (for testing MCP integration)

### Building

```bash
# Debug build
swift build

# Release build
swift build -c release
```

### Testing

```bash
# Run all tests
swift test

# Test MCP server manually
echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | .build/debug/AppleDocsTool
```

## Code Style

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Add documentation comments for public APIs
- Keep functions focused and concise

## Areas for Contribution

- **Additional Apple frameworks** - Expand framework support
- **Better Xcode project parsing** - Improve .xcodeproj parsing accuracy
- **Caching improvements** - Add persistent caching for documentation
- **Error handling** - Improve error messages and recovery
- **Tests** - Add unit and integration tests
- **Documentation** - Improve README and add examples

## Reporting Issues

When reporting issues, please include:

- macOS version
- Xcode/Swift version
- Steps to reproduce
- Expected vs actual behavior
- Relevant error messages

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
