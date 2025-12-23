import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

/// Service for interacting with iOS Simulator UI via macOS Accessibility APIs
final class SimulatorUIService: @unchecked Sendable {

    // MARK: - Error Types

    enum SimulatorUIError: Error, LocalizedError {
        case accessibilityNotEnabled
        case simulatorNotRunning
        case windowNotFound(deviceName: String?)
        case coordinateOutOfBounds(x: Int, y: Int)
        case eventPostFailed
        case invalidGesture(String)

        var errorDescription: String? {
            switch self {
            case .accessibilityNotEnabled:
                return "Accessibility permission not granted. Please enable it in System Settings > Privacy & Security > Accessibility for your terminal app."
            case .simulatorNotRunning:
                return "iOS Simulator is not running"
            case .windowNotFound(let name):
                if let name = name {
                    return "Simulator window not found for device: \(name)"
                }
                return "No simulator window found"
            case .coordinateOutOfBounds(let x, let y):
                return "Coordinates (\(x), \(y)) are outside the simulator bounds"
            case .eventPostFailed:
                return "Failed to post input event"
            case .invalidGesture(let msg):
                return "Invalid gesture: \(msg)"
            }
        }
    }

    // MARK: - Constants

    /// Approximate offsets for simulator window chrome
    private struct WindowChrome {
        static let titleBarHeight: CGFloat = 28
        static let bezelOffset: CGFloat = 0  // Modern simulators have minimal bezel
    }

    // MARK: - Accessibility Permission

    /// Check if accessibility permission is granted
    func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Prompt user to grant accessibility permission
    func requestAccessibility() {
        // Create options dictionary to prompt user
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings to Accessibility preferences
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Window Discovery

    /// Find simulator application PID
    private func findSimulatorPID() -> pid_t? {
        let apps = NSWorkspace.shared.runningApplications
        return apps.first(where: { $0.bundleIdentifier == "com.apple.iphonesimulator" })?.processIdentifier
    }

    /// Get all simulator windows
    func getSimulatorWindows() throws -> [SimulatorWindow] {
        guard checkAccessibility() else {
            throw SimulatorUIError.accessibilityNotEnabled
        }

        guard let pid = findSimulatorPID() else {
            throw SimulatorUIError.simulatorNotRunning
        }

        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return []
        }

        var simulatorWindows: [SimulatorWindow] = []

        for (index, window) in windows.enumerated() {
            // Get window title
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String ?? "Unknown"

            // Skip non-device windows (like Xcode, Console, etc.)
            // Device windows typically have names like "iPhone 16 Pro" or "iPad Pro"
            if title.isEmpty || title == "Simulator" {
                continue
            }

            // Get window bounds
            var posValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue)
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)

            var position = CGPoint.zero
            var size = CGSize.zero

            if let pos = posValue {
                AXValueGetValue(pos as! AXValue, .cgPoint, &position)
            }
            if let sz = sizeValue {
                AXValueGetValue(sz as! AXValue, .cgSize, &size)
            }

            let bounds = CGRect(origin: position, size: size)

            // Check if focused
            var focusedValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXFocusedAttribute as CFString, &focusedValue)
            let isFocused = focusedValue as? Bool ?? false

            simulatorWindows.append(SimulatorWindow(
                deviceName: title,
                windowId: index,
                bounds: bounds,
                isActive: isFocused
            ))
        }

        return simulatorWindows
    }

    /// Find a specific simulator window
    private func findWindow(deviceName: String?) throws -> (window: AXUIElement, bounds: CGRect, pid: pid_t) {
        guard checkAccessibility() else {
            throw SimulatorUIError.accessibilityNotEnabled
        }

        guard let pid = findSimulatorPID() else {
            throw SimulatorUIError.simulatorNotRunning
        }

        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            throw SimulatorUIError.windowNotFound(deviceName: deviceName)
        }

        for window in windows {
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String ?? ""

            // If looking for specific device, match name
            if let deviceName = deviceName {
                if !title.lowercased().contains(deviceName.lowercased()) {
                    continue
                }
            } else {
                // Skip non-device windows
                if title.isEmpty || title == "Simulator" {
                    continue
                }
            }

            // Get bounds
            var posValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue)
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)

            var position = CGPoint.zero
            var size = CGSize.zero

            if let pos = posValue {
                AXValueGetValue(pos as! AXValue, .cgPoint, &position)
            }
            if let sz = sizeValue {
                AXValueGetValue(sz as! AXValue, .cgSize, &size)
            }

            return (window, CGRect(origin: position, size: size), pid)
        }

        throw SimulatorUIError.windowNotFound(deviceName: deviceName)
    }

    // MARK: - Coordinate Translation

    /// Convert iOS coordinates to screen coordinates
    private func translateCoordinates(
        iosX: Int,
        iosY: Int,
        windowBounds: CGRect
    ) -> CGPoint {
        // The content area starts after the title bar
        let contentOriginX = windowBounds.origin.x + WindowChrome.bezelOffset
        let contentOriginY = windowBounds.origin.y + WindowChrome.titleBarHeight + WindowChrome.bezelOffset

        // Calculate content area size (window size minus chrome)
        // let contentWidth = windowBounds.size.width - (2 * WindowChrome.bezelOffset)
        // let contentHeight = windowBounds.size.height - WindowChrome.titleBarHeight - (2 * WindowChrome.bezelOffset)

        // For now, assume 1:1 mapping (no scaling)
        // A more sophisticated implementation would query the device scale
        let screenX = contentOriginX + CGFloat(iosX)
        let screenY = contentOriginY + CGFloat(iosY)

        return CGPoint(x: screenX, y: screenY)
    }

    // MARK: - Window Focus

    /// Bring simulator window to front
    private func focusWindow(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    // MARK: - Tap Actions

    /// Tap at iOS coordinates
    func tap(x: Int, y: Int, deviceName: String? = nil) async throws -> UIInteractionResult {
        let (window, bounds, _) = try findWindow(deviceName: deviceName)

        // Bring window to front
        focusWindow(window)

        // Small delay to ensure window is focused
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        let screenPoint = translateCoordinates(iosX: x, iosY: y, windowBounds: bounds)

        // Create and post mouse events
        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: screenPoint,
            mouseButton: .left
        ) else {
            throw SimulatorUIError.eventPostFailed
        }

        guard let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: screenPoint,
            mouseButton: .left
        ) else {
            throw SimulatorUIError.eventPostFailed
        }

        mouseDown.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: 25_000_000)  // 25ms
        mouseUp.post(tap: .cghidEventTap)

        return UIInteractionResult(
            success: true,
            action: "tap at (\(x), \(y))",
            deviceName: deviceName,
            message: nil
        )
    }

    /// Double tap at iOS coordinates
    func doubleTap(x: Int, y: Int, deviceName: String? = nil) async throws -> UIInteractionResult {
        _ = try await tap(x: x, y: y, deviceName: deviceName)
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        _ = try await tap(x: x, y: y, deviceName: deviceName)

        return UIInteractionResult(
            success: true,
            action: "double tap at (\(x), \(y))",
            deviceName: deviceName,
            message: nil
        )
    }

    /// Long press at iOS coordinates
    func longPress(x: Int, y: Int, duration: TimeInterval = 1.0, deviceName: String? = nil) async throws -> UIInteractionResult {
        let (window, bounds, _) = try findWindow(deviceName: deviceName)

        focusWindow(window)
        try await Task.sleep(nanoseconds: 50_000_000)

        let screenPoint = translateCoordinates(iosX: x, iosY: y, windowBounds: bounds)

        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: screenPoint,
            mouseButton: .left
        ) else {
            throw SimulatorUIError.eventPostFailed
        }

        guard let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: screenPoint,
            mouseButton: .left
        ) else {
            throw SimulatorUIError.eventPostFailed
        }

        mouseDown.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        mouseUp.post(tap: .cghidEventTap)

        return UIInteractionResult(
            success: true,
            action: "long press at (\(x), \(y)) for \(duration)s",
            deviceName: deviceName,
            message: nil
        )
    }

    // MARK: - Swipe/Drag Actions

    /// Swipe from one point to another
    func swipe(
        fromX: Int, fromY: Int,
        toX: Int, toY: Int,
        duration: TimeInterval = 0.3,
        deviceName: String? = nil
    ) async throws -> UIInteractionResult {
        let (window, bounds, _) = try findWindow(deviceName: deviceName)

        focusWindow(window)
        try await Task.sleep(nanoseconds: 50_000_000)

        let startPoint = translateCoordinates(iosX: fromX, iosY: fromY, windowBounds: bounds)
        let endPoint = translateCoordinates(iosX: toX, iosY: toY, windowBounds: bounds)

        // Number of intermediate steps
        let steps = max(10, Int(duration * 60))  // ~60fps
        let stepDelay = UInt64((duration / Double(steps)) * 1_000_000_000)

        // Mouse down at start
        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: startPoint,
            mouseButton: .left
        ) else {
            throw SimulatorUIError.eventPostFailed
        }

        mouseDown.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: 10_000_000)

        // Interpolate drag events
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let currentX = startPoint.x + (endPoint.x - startPoint.x) * t
            let currentY = startPoint.y + (endPoint.y - startPoint.y) * t
            let currentPoint = CGPoint(x: currentX, y: currentY)

            guard let drag = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: currentPoint,
                mouseButton: .left
            ) else {
                continue
            }

            drag.post(tap: .cghidEventTap)
            try await Task.sleep(nanoseconds: stepDelay)
        }

        // Mouse up at end
        guard let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: endPoint,
            mouseButton: .left
        ) else {
            throw SimulatorUIError.eventPostFailed
        }

        mouseUp.post(tap: .cghidEventTap)

        return UIInteractionResult(
            success: true,
            action: "swipe from (\(fromX), \(fromY)) to (\(toX), \(toY))",
            deviceName: deviceName,
            message: nil
        )
    }

    // MARK: - Keyboard Input

    /// Type text into the simulator
    func typeText(_ text: String, deviceName: String? = nil) async throws -> UIInteractionResult {
        let (window, _, _) = try findWindow(deviceName: deviceName)

        focusWindow(window)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Type each character using Unicode string input
        for char in text {
            let chars = Array(String(char).utf16)

            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
                continue
            }

            keyDown.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
            keyDown.post(tap: .cgAnnotatedSessionEventTap)

            guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                continue
            }
            keyUp.post(tap: .cgAnnotatedSessionEventTap)

            // Small delay between characters
            try await Task.sleep(nanoseconds: 20_000_000)  // 20ms
        }

        return UIInteractionResult(
            success: true,
            action: "type \"\(text)\"",
            deviceName: deviceName,
            message: nil
        )
    }

    // MARK: - Hardware Buttons

    /// Key codes for simulator shortcuts
    private struct KeyCodes {
        static let h: CGKeyCode = 4      // H key
        static let l: CGKeyCode = 37     // L key
        static let s: CGKeyCode = 1      // S key
        static let k: CGKeyCode = 40     // K key
        static let upArrow: CGKeyCode = 126
        static let downArrow: CGKeyCode = 125
    }

    /// Press a hardware button
    func pressButton(_ button: HardwareButton, deviceName: String? = nil) async throws -> UIInteractionResult {
        let (window, _, _) = try findWindow(deviceName: deviceName)

        focusWindow(window)
        try await Task.sleep(nanoseconds: 50_000_000)

        let (keyCode, flags): (CGKeyCode, CGEventFlags) = switch button {
        case .home:
            (KeyCodes.h, [.maskCommand, .maskShift])  // Cmd+Shift+H
        case .lock:
            (KeyCodes.l, [.maskCommand])  // Cmd+L
        case .volumeUp:
            (KeyCodes.upArrow, [.maskCommand])  // Cmd+Up
        case .volumeDown:
            (KeyCodes.downArrow, [.maskCommand])  // Cmd+Down
        case .ringer:
            (KeyCodes.s, [.maskCommand, .maskShift])  // Cmd+Shift+S (toggle ringer)
        case .screenshot:
            (KeyCodes.s, [.maskCommand])  // Cmd+S
        case .keyboard:
            (KeyCodes.k, [.maskCommand])  // Cmd+K (toggle keyboard)
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw SimulatorUIError.eventPostFailed
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        try await Task.sleep(nanoseconds: 50_000_000)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        return UIInteractionResult(
            success: true,
            action: "press \(button.rawValue) button",
            deviceName: deviceName,
            message: nil
        )
    }
}
