# Control Simulator

Manage iOS/watchOS/tvOS/visionOS simulators - boot, install apps, and control device state.

## When to Use

- Need to test an app in the simulator
- Setting up a specific device configuration
- Capturing screenshots or video
- Testing push notifications or location
- Managing multiple simulator devices

## Quick Start

### List Available Devices

```bash
# All devices
xcrun simctl list devices

# Only booted devices
xcrun simctl list devices | grep Booted

# Available device types
xcrun simctl list devicetypes

# Available runtimes (iOS versions)
xcrun simctl list runtimes
```

### Boot and Shutdown

```bash
# Boot a device (use device name or UUID)
xcrun simctl boot "iPhone 16"

# Shutdown a device
xcrun simctl shutdown "iPhone 16"

# Shutdown all simulators
xcrun simctl shutdown all

# Open Simulator.app with a device
open -a Simulator --args -CurrentDeviceUDID $(xcrun simctl list devices | grep "iPhone 16" | grep -oE "[A-F0-9-]{36}")
```

### Get Device UUID

```bash
# Find UUID for a specific device
xcrun simctl list devices | grep "iPhone 16"
# Output: iPhone 16 (XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX) (Booted)

# Get just the UUID
DEVICE_UUID=$(xcrun simctl list devices available | grep "iPhone 16 Pro (" | head -1 | grep -oE "[A-F0-9-]{36}")
echo $DEVICE_UUID
```

## App Management

### Install and Launch

```bash
# Install an app (needs .app bundle, not .ipa)
xcrun simctl install booted /path/to/MyApp.app

# Launch an app
xcrun simctl launch booted com.example.myapp

# Launch and wait for debugger
xcrun simctl launch -w booted com.example.myapp

# Launch with arguments
xcrun simctl launch booted com.example.myapp --arg1 value1
```

### Terminate and Uninstall

```bash
# Terminate running app
xcrun simctl terminate booted com.example.myapp

# Uninstall app
xcrun simctl uninstall booted com.example.myapp

# List installed apps
xcrun simctl listapps booted
```

## Screenshots and Video

### Screenshot

```bash
# Capture screenshot (PNG)
xcrun simctl io booted screenshot screenshot.png

# Different formats
xcrun simctl io booted screenshot --type=jpeg screenshot.jpg
xcrun simctl io booted screenshot --type=png screenshot.png

# With mask (device frame)
xcrun simctl io booted screenshot --mask=black screenshot.png
```

### Record Video

```bash
# Start recording
xcrun simctl io booted recordVideo output.mov

# Press Ctrl+C to stop recording

# With specific codec
xcrun simctl io booted recordVideo --codec=h264 output.mp4
```

## Location and Push Notifications

### Set Location

```bash
# Set specific coordinates
xcrun simctl location booted set 37.7749,-122.4194

# Clear location (return to default)
xcrun simctl location booted clear
```

### Send Push Notification

```bash
# Create payload file
cat > /tmp/push.json << 'EOF'
{
  "aps": {
    "alert": {
      "title": "Test Notification",
      "body": "Hello from simctl!"
    },
    "badge": 1,
    "sound": "default"
  }
}
EOF

# Send to app
xcrun simctl push booted com.example.myapp /tmp/push.json
```

## Privacy and Permissions

```bash
# Grant permission
xcrun simctl privacy booted grant photos com.example.myapp
xcrun simctl privacy booted grant camera com.example.myapp
xcrun simctl privacy booted grant location com.example.myapp

# Revoke permission
xcrun simctl privacy booted revoke photos com.example.myapp

# Reset all permissions
xcrun simctl privacy booted reset all com.example.myapp
```

Available services: `all`, `calendar`, `contacts`, `location`, `photos`, `camera`, `microphone`, `media-library`, `motion`, `reminders`, `siri`

## Status Bar Override

```bash
# Set perfect status bar for screenshots
xcrun simctl status_bar booted override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --cellularMode active \
  --cellularBars 4

# Clear overrides
xcrun simctl status_bar booted clear
```

## Deep Links and URLs

```bash
# Open URL in simulator
xcrun simctl openurl booted "https://example.com"

# Test deep links
xcrun simctl openurl booted "myapp://path/to/content"
```

## Clipboard

```bash
# Copy text to simulator clipboard
echo "Hello" | xcrun simctl pbcopy booted

# Get text from simulator clipboard
xcrun simctl pbpaste booted
```

## Device Management

### Create and Delete

```bash
# Create new device
xcrun simctl create "My Test Phone" "iPhone 16" "iOS-18-0"

# Delete device
xcrun simctl delete "My Test Phone"

# Erase device (reset to clean state)
xcrun simctl erase "iPhone 16"

# Clone device
xcrun simctl clone "iPhone 16" "iPhone 16 Copy"
```

## Common Workflows

### Fresh Test Environment

```bash
# Erase, boot, install, launch
xcrun simctl erase "iPhone 16" && \
xcrun simctl boot "iPhone 16" && \
xcrun simctl install booted MyApp.app && \
xcrun simctl launch booted com.example.myapp
```

### Screenshot with Perfect Status Bar

```bash
xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 && \
xcrun simctl io booted screenshot --mask=black screenshot.png && \
xcrun simctl status_bar booted clear
```

## Tips

- Use `booted` as device name to target the currently running simulator
- Device names with spaces need quotes: `"iPhone 16 Pro Max"`
- UUIDs are more reliable than names for scripting
- `xcrun simctl help` shows all available commands
- Apps must be built for simulator (x86_64/arm64 simulator slice)

## MCP Fallback

For structured data or complex operations:
- `simctl_list_devices` - JSON list of devices with state
- `simctl_device_control` - Boot/shutdown/create/delete
- `simctl_app_control` - Install/launch/terminate
- `simctl_screenshot` / `simctl_record_video` - Media capture
