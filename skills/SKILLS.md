# Apple Development Skills

This directory contains reusable skills for Apple platform development. Each skill provides workflows and commands that can be executed directly, with MCP tools available as fallbacks for advanced use cases.

## How to Use

1. **Discover** - Read this file to see available skills
2. **Load** - Read the SKILL.md for the capability you need
3. **Execute** - Run the shell commands directly
4. **Fallback** - Use MCP tools only when shell commands aren't sufficient

## Available Skills

| Skill | Description | Shell-Only? |
|-------|-------------|-------------|
| [analyze-project](analyze-project/SKILL.md) | Understand project structure, dependencies, and symbols | Yes |
| [build-and-test](build-and-test/SKILL.md) | Build Swift packages/Xcode projects and run tests | Yes |
| [lookup-docs](lookup-docs/SKILL.md) | Find Apple API and dependency documentation | Yes |
| [control-simulator](control-simulator/SKILL.md) | Manage simulators, install apps, capture media | Yes |
| [ui-interact](ui-interact/SKILL.md) | Automate UI interactions in simulator | Partial* |
| [profile-app](profile-app/SKILL.md) | Profile performance with Instruments | Yes |

*ui-interact requires MCP tools for coordinate-based tapping and visual state inspection

## Skills vs MCP Tools

**Skills** are self-contained workflows using standard shell commands (`swift`, `xcrun simctl`, `xcodebuild`, etc.). They're:
- Lower token cost (no tool definitions needed)
- Portable (work anywhere with Xcode installed)
- Composable (chain commands together)

**MCP Tools** provide structured data and advanced capabilities:
- Parsed JSON output instead of text parsing
- Accessibility API integration (UI automation)
- Complex operations as single calls

## When to Use MCP

Use MCP tools when you need:
1. **Structured data** - JSON instead of parsing command output
2. **UI automation** - Tapping, swiping based on screen content
3. **Symbol graphs** - Parsed Swift symbols with full metadata
4. **Error handling** - Structured errors vs exit codes

## Quick Reference

```bash
# Project Analysis
cat Package.swift                    # View project config
swift build                          # Build project
swift test                           # Run tests
grep -rn "struct " Sources/          # Find types

# Simulator Control
xcrun simctl list devices            # List simulators
xcrun simctl boot "iPhone 16"        # Boot simulator
xcrun simctl install booted App.app  # Install app
xcrun simctl io booted screenshot x.png  # Screenshot

# Documentation
# https://developer.apple.com/documentation/{framework}/{symbol}

# Profiling
xcrun xctrace list templates         # List profilers
xcrun xctrace record --template "Time Profiler" --attach PID
```

## File Structure

```
skills/
├── SKILLS.md                 # This file - skill index
├── analyze-project/
│   └── SKILL.md             # Project analysis workflows
├── build-and-test/
│   └── SKILL.md             # Build and test workflows
├── lookup-docs/
│   └── SKILL.md             # Documentation lookup
├── control-simulator/
│   └── SKILL.md             # Simulator management
├── ui-interact/
│   └── SKILL.md             # UI automation
└── profile-app/
    └── SKILL.md             # Performance profiling
```
