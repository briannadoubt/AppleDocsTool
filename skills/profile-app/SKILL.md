# Profile App

Profile application performance using Instruments - find CPU bottlenecks, memory leaks, and more.

## When to Use

- App feels slow or janky
- Investigating memory leaks
- Optimizing CPU usage
- Analyzing energy impact
- Debugging performance regressions

## Quick Start

### List Available Templates

```bash
# See all profiling templates
xcrun xctrace list templates
```

Common templates:
- **Time Profiler** - CPU usage and call stacks
- **Allocations** - Memory allocation tracking
- **Leaks** - Memory leak detection
- **System Trace** - Low-level system events
- **Energy Log** - Battery/energy usage
- **Network** - Network activity
- **File Activity** - Disk I/O

### Profile a Running App

```bash
# Find your app's PID
pgrep -l MyApp

# Profile with Time Profiler for 10 seconds
xcrun xctrace record \
  --template "Time Profiler" \
  --attach $(pgrep MyApp) \
  --time-limit 10s \
  --output /tmp/profile.trace
```

### Profile App Launch

```bash
# Profile from launch
xcrun xctrace record \
  --template "Time Profiler" \
  --launch -- /path/to/MyApp.app/Contents/MacOS/MyApp \
  --time-limit 30s \
  --output /tmp/launch.trace
```

### Profile on Simulator

```bash
# First, get the app's PID on the simulator
xcrun simctl spawn booted launchctl list | grep myapp

# Profile simulator process
xcrun xctrace record \
  --template "Time Profiler" \
  --device "iPhone 16" \
  --attach com.example.myapp \
  --time-limit 10s \
  --output /tmp/profile.trace
```

## Analyzing Results

### Open in Instruments

```bash
# Open trace file in Instruments GUI
open /tmp/profile.trace
```

### Export Data (CLI)

```bash
# List available instruments in trace
xcrun xctrace export --input /tmp/profile.trace --toc

# Export to XML
xcrun xctrace export --input /tmp/profile.trace --output /tmp/export.xml
```

## Common Profiling Scenarios

### CPU Performance

```bash
# Time Profiler - see where CPU time is spent
xcrun xctrace record \
  --template "Time Profiler" \
  --attach $(pgrep MyApp) \
  --time-limit 30s \
  --output /tmp/cpu.trace
```

Look for:
- Hot spots (functions with high "self time")
- Deep call stacks
- Main thread blocking

### Memory Issues

```bash
# Allocations - track all memory allocations
xcrun xctrace record \
  --template "Allocations" \
  --attach $(pgrep MyApp) \
  --time-limit 30s \
  --output /tmp/memory.trace

# Leaks - find memory leaks
xcrun xctrace record \
  --template "Leaks" \
  --attach $(pgrep MyApp) \
  --time-limit 60s \
  --output /tmp/leaks.trace
```

### UI Responsiveness

```bash
# System Trace for UI hangs
xcrun xctrace record \
  --template "System Trace" \
  --attach $(pgrep MyApp) \
  --time-limit 10s \
  --output /tmp/system.trace
```

### Energy/Battery

```bash
# Energy profiling (device recommended)
xcrun xctrace record \
  --template "Energy Log" \
  --attach $(pgrep MyApp) \
  --time-limit 60s \
  --output /tmp/energy.trace
```

## Instruments from Xcode

For more complex analysis, use Instruments.app:

```bash
# Open Instruments
open -a Instruments

# Or with a specific template
open -a Instruments --args -t "Time Profiler"
```

## Quick Performance Checks

### Memory Footprint

```bash
# Check memory usage
ps aux | grep MyApp | awk '{print $6/1024 " MB"}'

# Detailed memory (macOS)
vmmap $(pgrep MyApp) | tail -5
```

### CPU Usage

```bash
# Watch CPU usage
top -pid $(pgrep MyApp) -l 5
```

### Open Files

```bash
# Check file handles
lsof -p $(pgrep MyApp) | wc -l
```

## Best Practices

1. **Profile release builds** - Debug builds have different performance characteristics
2. **Profile on device** - Simulator performance differs from real hardware
3. **Establish baseline** - Profile before making changes to compare
4. **Profile specific scenarios** - Don't just profile "normal use"
5. **Multiple runs** - Performance varies; average multiple profiles

## Tips

- Time limit prevents runaway trace files (they get big)
- Use `--template` exactly as shown by `xctrace list templates`
- Trace files can be huge; delete when done
- GUI analysis in Instruments.app is much easier than CLI export
- For simulator profiling, target the Simulator process hosting your app

## MCP Fallback

For integrated profiling with parsed results:
- `instruments_profile` - Profile and get parsed summary
- `list_instruments_templates` - List available templates

These tools handle the complexity of finding the right process and return structured summaries instead of raw trace files.
