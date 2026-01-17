# UI Interact

Automate simulator UI interactions - tap, swipe, type, and verify screen content.

## When to Use

- Testing UI flows end-to-end
- Automating repetitive manual testing
- Capturing screenshots of specific screens
- Verifying UI state after actions

## Prerequisites

**Important:** This skill requires the AppleDocsTool MCP server for UI automation, as it uses macOS Accessibility APIs that can't be accessed via shell commands alone.

For basic interactions, you can use `xcrun simctl` directly. For visual state inspection and coordinate-based interactions, you'll need the MCP tools.

## Basic Interactions (Shell)

### Keyboard Input

```bash
# Type text (requires app with focused text field)
# Note: This sends keystrokes to the Simulator app
osascript -e 'tell application "Simulator" to activate'
osascript -e 'tell application "System Events" to keystroke "Hello World"'

# Press Return
osascript -e 'tell application "System Events" to key code 36'

# Press Escape
osascript -e 'tell application "System Events" to key code 53'
```

### Hardware Buttons via simctl

```bash
# Home button
xcrun simctl ui booted home

# Lock device (if supported)
# Note: Not all button types available via simctl
```

### Open URLs (Deep Links)

```bash
# Navigate via deep link
xcrun simctl openurl booted "myapp://screen/settings"
xcrun simctl openurl booted "https://example.com/login"
```

## Visual State Inspection

### Screenshot + Analysis

```bash
# Take screenshot
xcrun simctl io booted screenshot /tmp/screen.png

# View it (opens Preview)
open /tmp/screen.png
```

For OCR and coordinate extraction, use the MCP tool `simulator_ui_state` which returns:
- Screenshot as base64 image
- OCR-extracted text with bounding boxes
- Tap coordinates for each text element

## Coordinate-Based Interactions

The MCP tools provide coordinate-based interaction:

1. **Get UI State** (`simulator_ui_state`)
   - Returns screenshot + all visible text with coordinates

2. **Find Text** (`simulator_find_text`)
   - Search for specific text and get its tap coordinates

3. **Interact** (`simulator_interact`)
   - Tap at coordinates
   - Swipe between points
   - Type text
   - Press hardware buttons

### Workflow Example

```
1. Call simulator_ui_state to see the screen
2. Find the "Login" button coordinates from the response
3. Call simulator_interact with action="tap" at those coordinates
4. Call simulator_ui_state again to verify the result
```

## AppleScript Fallbacks

For basic automation without MCP:

```bash
# Click at coordinates (screen coordinates, not simulator)
osascript -e 'tell application "System Events" to click at {500, 400}'

# More reliable: Use Accessibility
osascript << 'EOF'
tell application "Simulator" to activate
delay 0.5
tell application "System Events"
    tell process "Simulator"
        -- Click in the simulator window
        click at {500, 400}
    end tell
end tell
EOF
```

## Testing Workflows

### Login Flow Test

```bash
# 1. Launch app fresh
xcrun simctl terminate booted com.example.myapp
xcrun simctl launch booted com.example.myapp

# 2. Wait for launch
sleep 2

# 3. Take screenshot to see initial state
xcrun simctl io booted screenshot /tmp/step1.png

# 4. Use MCP simulator_interact to tap login button
# 5. Use MCP simulator_interact to type credentials
# 6. Screenshot final state
xcrun simctl io booted screenshot /tmp/step2.png
```

### Screenshot Tour

```bash
# Navigate through screens capturing each
for screen in home settings profile; do
  xcrun simctl openurl booted "myapp://$screen"
  sleep 1
  xcrun simctl io booted screenshot "/tmp/$screen.png"
done
```

## Tips

- Always wait (sleep) after actions for UI to settle
- Use deep links when possible - more reliable than tap coordinates
- Screenshot before AND after interactions to verify
- Reset app state between test runs with `xcrun simctl privacy booted reset`
- The simulator must be visible and active for UI interactions

## Limitations

- Shell-based automation is limited - can't inspect UI elements
- Coordinate-based tapping is fragile if UI changes
- AppleScript automation requires Simulator to be frontmost
- For robust UI testing, consider XCUITest instead

## MCP Tools (Required for Full Functionality)

- `simulator_ui_state` - Get screenshot + OCR text with coordinates
- `simulator_find_text` - Find specific text and get tap coordinates
- `simulator_interact` - Tap, swipe, type, press buttons

These tools use macOS Accessibility APIs to interact with the simulator window directly, providing reliable coordinate-based automation.
