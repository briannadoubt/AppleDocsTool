# AppleDocsTool

Apple development tools for Claude Code - simulator UI automation, project analysis, build/test, and documentation lookup.

## Install

**From GitHub (works now):**
```bash
/plugin marketplace add briannadoubt/claude-marketplace
/plugin install apple-docs@briannadoubt
```

**From official marketplace (after approval):**
```bash
/plugin install apple-docs
```

<details>
<summary>Alternative: Local install</summary>

```bash
git clone https://github.com/briannadoubt/AppleDocsTool.git
claude plugin install ./AppleDocsTool --scope user
```

Or MCP-only (no skills):
```bash
cd AppleDocsTool && swift build -c release
claude mcp add apple-docs .build/release/apple-docs
```
</details>

**Verify:**
```bash
/plugin list    # should show apple-docs
```

## Architecture

This tool uses a **skills-first approach** for efficiency:

| Layer | What | Token Cost |
|-------|------|------------|
| **Skills** | Shell commands in `skills/` directory | ~0 (just file reads) |
| **MCP (minimal)** | 3 UI automation tools | ~2K tokens |
| **MCP (full)** | All 33 tools | ~30K tokens |

By default, the server exposes only 3 tools that **require** macOS Accessibility APIs. Everything else can be done with shell commands documented in the skills.

## Skills

Claude discovers capabilities by reading `skills/SKILLS.md`:

| Skill | Description | Example Commands |
|-------|-------------|------------------|
| [analyze-project](skills/analyze-project/SKILL.md) | Understand project structure | `cat Package.swift`, `grep -rn "struct"` |
| [build-and-test](skills/build-and-test/SKILL.md) | Build and test | `swift build`, `swift test` |
| [lookup-docs](skills/lookup-docs/SKILL.md) | Find documentation | Apple docs URLs, GitHub READMEs |
| [control-simulator](skills/control-simulator/SKILL.md) | Manage simulators | `xcrun simctl boot`, `xcrun simctl install` |
| [profile-app](skills/profile-app/SKILL.md) | Profile performance | `xcrun xctrace record` |
| [ui-interact](skills/ui-interact/SKILL.md) | UI automation | Requires MCP tools |

## MCP Tools

### Default (Minimal Server)

Only tools that can't be done with shell commands:

| Tool | Description |
|------|-------------|
| `simulator_ui_state` | Get screenshot + OCR text with tap coordinates |
| `simulator_interact` | Tap, swipe, type text, press hardware buttons |
| `simulator_find_text` | Find text on screen, get coordinates |

### Full Server

For all 33 tools (project symbols, Apple docs, build/test, profiling, etc.):

```bash
# Configure with --full flag
claude mcp add apple-docs ~/.mint/bin/apple-docs --args --full
```

<details>
<summary>Full tool list</summary>

**Project Analysis**
- `get_project_symbols` - Extract types, functions, properties
- `get_project_dependencies` - List dependencies with versions
- `get_symbol_documentation` - Detailed docs for specific symbols
- `get_project_summary` - Quick project overview
- `search_symbols` - Fuzzy search across project and Apple frameworks

**Documentation**
- `lookup_apple_api` - Apple framework documentation
- `get_dependency_docs` - Fetch README from GitHub

**Build & Test**
- `swift_build` - Build Swift packages
- `swift_test` - Run tests with structured output
- `swift_run` - Run executables
- `xcodebuild_build` - Build Xcode projects
- `xcodebuild_test` - Run Xcode tests
- `list_schemes` - List available schemes
- `list_destinations` - List simulators/devices

**Profiling**
- `instruments_profile` - Profile with any Instruments template
- `list_instruments_templates` - List available templates

**Simulator Control**
- `simctl_list_devices` - List simulators
- `simctl_list_runtimes` - List iOS/tvOS/watchOS versions
- `simctl_device_control` - Boot, shutdown, create, delete
- `simctl_app_install` - Install apps
- `simctl_app_control` - Launch, terminate, uninstall
- `simctl_app_info` - Get app info
- `simctl_screenshot` - Capture screenshots
- `simctl_record_video` - Record video
- `simctl_location` - Set GPS location
- `simctl_push` - Send push notifications
- `simctl_privacy` - Manage permissions
- `simctl_status_bar` - Override status bar
- `simctl_pasteboard` - Clipboard access
- `simctl_open_url` - Open URLs/deep links

**UI Automation**
- `simulator_ui_state` - Screenshot + OCR
- `simulator_interact` - Tap, swipe, type, buttons
- `simulator_find_text` - Find text coordinates

</details>

## Usage Examples

### With Skills (Recommended)

Claude reads the skill files and executes shell commands directly:

```
You: Analyze this Swift project

Claude: [Reads skills/analyze-project/SKILL.md]
        [Runs: cat Package.swift]
        [Runs: grep -rn "struct\|class" Sources/]
        Here's the project structure...
```

### With MCP Tools

For UI automation (the only thing that needs MCP):

```
You: Tap the Login button in the simulator

Claude: [Calls simulator_find_text(text: "Login")]
        Found at (197, 445)
        [Calls simulator_interact(action: "tap", x: 197, y: 445)]
        Tapped Login button
```

## Requirements

- macOS 13.0+
- Swift 6.0+ (Xcode 16+)
- [Claude Code](https://claude.ai/code)

## Development

```bash
# Build
swift build

# Test
swift test

# Run minimal server
swift run

# Run full server
swift run apple-docs --full
```

### Project Structure

```
AppleDocsTool/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── .mcp.json                    # MCP server config
├── Package.swift
├── skills/                      # Shell-based workflows
│   ├── SKILLS.md               # Skill index
│   ├── analyze-project/
│   ├── build-and-test/
│   ├── control-simulator/
│   ├── lookup-docs/
│   ├── profile-app/
│   └── ui-interact/
└── Sources/
    └── AppleDocsTool/
        ├── Server/
        │   ├── MinimalMCPServer.swift  # 3 UI tools (default)
        │   └── MCPServer.swift         # 33 tools (--full)
        ├── Services/                    # Core functionality
        └── Models/                      # Data types
```

## License

MIT License - see [LICENSE](LICENSE) for details.
