# AGENTS.md instructions for /Users/bri/dev/AppleDocsTool

<INSTRUCTIONS>
## Skills
A skill is a set of local instructions to follow that is stored in a `SKILL.md` file. Below is the list of skills that can be used. Each entry includes a name, description, and file path so you can open the source for full instructions when using a specific skill.
### Available skills
- skill-creator: Guide for creating effective skills. This skill should be used when users want to create a new skill (or update an existing skill) that extends Codex's capabilities with specialized knowledge, workflows, or tool integrations. (file: /Users/bri/.codex/skills/.system/skill-creator/SKILL.md)
- skill-installer: Install Codex skills into $CODEX_HOME/skills from a curated list or a GitHub repo path. Use when a user asks to list installable skills, install a curated skill, or install a skill from another repo (including private repos). (file: /Users/bri/.codex/skills/.system/skill-installer/SKILL.md)
### How to use skills
- Discovery: The list above is the skills available in this session (name + description + file path). Skill bodies live on disk at the listed paths.
- Trigger rules: If the user names a skill (with `$SkillName` or plain text) OR the task clearly matches a skill's description shown above, you must use that skill for that turn. Multiple mentions mean use them all. Do not carry skills across turns unless re-mentioned.
- Missing/blocked: If a named skill isn't in the list or the path can't be read, say so briefly and continue with the best fallback.
- How to use a skill (progressive disclosure):
  1) After deciding to use a skill, open its `SKILL.md`. Read only enough to follow the workflow.
  2) When `SKILL.md` references relative paths (e.g., `scripts/foo.py`), resolve them relative to the skill directory listed above first, and only consider other paths if needed.
  3) If `SKILL.md` points to extra folders such as `references/`, load only the specific files needed for the request; don't bulk-load everything.
  4) If `scripts/` exist, prefer running or patching them instead of retyping large code blocks.
  5) If `assets/` or templates exist, reuse them instead of recreating from scratch.
- Coordination and sequencing:
  - If multiple skills apply, choose the minimal set that covers the request and state the order you'll use them.
  - Announce which skill(s) you're using and why (one short line). If you skip an obvious skill, say why.
- Context hygiene:
  - Keep context small: summarize long sections instead of pasting them; only load extra files when needed.
  - Avoid deep reference-chasing: prefer opening only files directly linked from `SKILL.md` unless you're blocked.
  - When variants exist (frameworks, providers, domains), pick only the relevant reference file(s) and note that choice.
- Safety and fallback: If a skill can't be applied cleanly (missing files, unclear instructions), state the issue, pick the next-best approach, and continue.

## AppleDocsTool: Codex-Formatted Tooling

This repo ships Claude-oriented tooling (`.claude/`, `.claude-plugin/`) plus an MCP server and a set of shell-first workflows in `skills/`. Codex should treat them as follows:

### MCP (Codex)

- MCP config lives in `.mcp.json`.
- Servers:
  1) `apple-docs` (minimal; default): UI automation only (`simulator_ui_state`, `simulator_interact`, `simulator_find_text`)
  2) `apple-docs-full` (full): all tools (build/test/docs lookup/simctl + UI automation)
- Tool name format in Codex:
  - Minimal: `mcp__apple-docs__<tool>`
  - Full: `mcp__apple-docs-full__<tool>`
- Full tool set (from the server implementation):
  - `get_project_summary`, `get_project_symbols`, `get_project_dependencies`, `search_symbols`, `get_symbol_documentation`
  - `lookup_apple_api`, `get_dependency_docs`
  - `swift_build`, `swift_test`, `swift_run`
  - `xcodebuild_build`, `xcodebuild_test`, `list_schemes`, `list_destinations`
  - `simctl_list_devices`, `simctl_list_runtimes`, `simctl_device_control`
  - `simctl_app_install`, `simctl_app_control`, `simctl_app_info`
  - `simctl_screenshot`, `simctl_record_video`, `simctl_location`, `simctl_push`, `simctl_privacy`, `simctl_status_bar`, `simctl_pasteboard`, `simctl_open_url`
  - `simulator_ui_state`, `simulator_find_text`, `simulator_interact`

### Shell-First Workflows

Prefer the repo workflows in `skills/` for most tasks (low token cost, easy to compose):
- `skills/analyze-project/SKILL.md`
- `skills/build-and-test/SKILL.md`
- `skills/lookup-docs/SKILL.md`
- `skills/control-simulator/SKILL.md`
- `skills/profile-app/SKILL.md`
- `skills/ui-interact/SKILL.md` (uses MCP for coordinate-based UI automation)

### Codex Skills (Installed)

These repo workflows have been mirrored into Codex skills under:
- `/Users/bri/.codex/skills/apple-docs-analyze-project`
- `/Users/bri/.codex/skills/apple-docs-build-and-test`
- `/Users/bri/.codex/skills/apple-docs-lookup-docs`
- `/Users/bri/.codex/skills/apple-docs-control-simulator`
- `/Users/bri/.codex/skills/apple-docs-profile-app`
- `/Users/bri/.codex/skills/apple-docs-ui-interact`

If Codex doesn’t pick them up immediately, restart Codex.
</INSTRUCTIONS>
