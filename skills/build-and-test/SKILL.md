# Build and Test

Build Swift packages and Xcode projects, run tests, and interpret results.

## When to Use

- Building a project to check for errors
- Running unit tests
- Checking code coverage
- Debugging build failures

## Quick Start

### Swift Package Manager

```bash
# Build (debug)
swift build

# Build (release)
swift build -c release

# Build specific target
swift build --target MyTarget

# Build with verbose output
swift build -v
```

### Run Tests

```bash
# Run all tests
swift test

# Run specific test class
swift test --filter MyTests

# Run specific test method
swift test --filter MyTests/testSomething

# Run with verbose output (see each test)
swift test -v

# Run tests in parallel
swift test --parallel
```

### Code Coverage

```bash
# Enable coverage
swift test --enable-code-coverage

# Find coverage data
COVERAGE_PATH=$(swift test --enable-code-coverage 2>&1 | grep "llvm-cov" | sed 's/.*export //' | awk '{print $1}')

# View coverage report (requires successful test run first)
xcrun llvm-cov report \
  .build/debug/YourPackagePackageTests.xctest/Contents/MacOS/YourPackagePackageTests \
  -instr-profile=.build/debug/codecov/default.profdata
```

## Xcode Projects

```bash
# List available schemes
xcodebuild -list

# Build a scheme
xcodebuild -scheme MyScheme -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -scheme MyScheme -destination 'platform=iOS Simulator,name=iPhone 16' test

# Build for specific SDK
xcodebuild -scheme MyScheme -sdk iphonesimulator build

# Clean build
xcodebuild -scheme MyScheme clean build
```

## Interpreting Build Errors

### Common Patterns

```bash
# Extract just errors from build output
swift build 2>&1 | grep -E "error:|warning:"

# Get context around errors
swift build 2>&1 | grep -B2 -A2 "error:"
```

### Error Types

| Pattern | Meaning |
|---------|---------|
| `cannot find 'X' in scope` | Missing import or typo |
| `type 'X' has no member 'Y'` | Wrong method/property name |
| `cannot convert value` | Type mismatch |
| `missing argument` | Function call missing required param |
| `ambiguous use of` | Multiple matching overloads |

## Interpreting Test Failures

```bash
# Run tests and capture output
swift test 2>&1 | tee test-output.txt

# Find failures
grep -E "failed|FAIL" test-output.txt

# Get failure details
grep -B5 -A10 "failed" test-output.txt
```

### Test Output Format

```
Test Case '-[ModuleTests.MyTests testExample]' started.
/path/to/file.swift:42: error: -[ModuleTests.MyTests testExample] : XCTAssertEqual failed: ("1") is not equal to ("2")
Test Case '-[ModuleTests.MyTests testExample]' failed (0.001 seconds).
```

## Quick Fixes

### "No such module"
```bash
# Resolve dependencies first
swift package resolve
swift build
```

### Clean Build
```bash
# Swift Package
rm -rf .build && swift build

# Xcode
xcodebuild clean && xcodebuild build -scheme MyScheme
```

### Update Dependencies
```bash
swift package update
```

## Run Executables

```bash
# Run default executable
swift run

# Run specific product
swift run MyExecutable

# Run with arguments
swift run MyExecutable --arg1 value1

# Run release build
swift run -c release MyExecutable
```

## Tips

- Always run `swift build` before `swift test` to get cleaner error output
- Use `-v` (verbose) when you need to see what's happening
- Filter tests with `--filter` to speed up iteration
- Check `Package.swift` for available targets and products

## MCP Fallback

For structured output or advanced features:
- `swift_build` - Returns parsed errors/warnings as JSON
- `swift_test` - Returns test results with pass/fail counts
- `swift_run` - Captures stdout/stderr separately
