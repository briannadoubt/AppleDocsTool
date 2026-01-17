import Foundation
import MCP

/// Minimal MCP Server - UI automation only.
///
/// This server exposes ONLY the tools that require macOS Accessibility APIs
/// and cannot be replicated with shell commands.
///
/// For everything else, use shell commands or the skills in /skills/:
/// - Project analysis: `cat Package.swift`, `grep`, `swift build`
/// - Building/testing: `swift build`, `swift test`, `xcodebuild`
/// - Simulator control: `xcrun simctl`
/// - Profiling: `xcrun xctrace`
/// - Apple docs: https://developer.apple.com/documentation/{framework}/{symbol}
///
/// Pass --full to main.swift for all 33 tools.
public final class MinimalMCPServer: @unchecked Sendable {
    private let server: Server
    private let simulatorService = SimulatorService()
    private let simulatorUIService = SimulatorUIService()

    public init() {
        self.server = Server(
            name: "apple-docs",
            version: "2.0.0",
            capabilities: .init(
                tools: .init(listChanged: true)
            )
        )
    }

    public func start() async throws {
        await registerToolHandlers()
        let transport = StdioTransport()
        try await server.start(transport: transport)
    }

    private func registerToolHandlers() async {
        await server.withMethodHandler(ListTools.self) { [weak self] _ in
            guard self != nil else { return .init(tools: []) }
            return .init(tools: Self.availableTools)
        }

        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self = self else {
                return .init(content: [.text("Server error")], isError: true)
            }
            return await self.handleToolCall(params)
        }
    }

    // MARK: - Tools (3 UI Automation Tools Only)

    private static var availableTools: [Tool] {
        [
            Tool(
                name: "simulator_ui_state",
                description: """
                    Get the current visual state of a simulator: screenshot + OCR text with tap coordinates.

                    This is the ONLY way to:
                    1. See what's on screen (returns screenshot path)
                    2. Get coordinates for tappable elements
                    3. Extract text via OCR

                    WORKFLOW:
                    1. Call this to see current state
                    2. Find the element you want to interact with
                    3. Use simulator_interact with the coordinates
                    4. Call this again to verify the result
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Simulator device UUID or 'booted' (default: booted)")
                        ])
                    ]),
                    "required": .array([])
                ])
            ),
            Tool(
                name: "simulator_interact",
                description: """
                    Interact with simulator UI: tap, swipe, type text, or press hardware buttons.

                    IMPORTANT: Get coordinates from simulator_ui_state or simulator_find_text first!

                    Actions:
                    - tap: Click at (x, y) coordinates
                    - swipe: Drag from (x, y) to (to_x, to_y)
                    - type: Enter text (requires focused text field)
                    - button: Press home, lock, volumeUp, volumeDown
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "description": .string("Action type: tap, swipe, type, button"),
                            "enum": .array([.string("tap"), .string("swipe"), .string("type"), .string("button")])
                        ]),
                        "device_name": .object([
                            "type": .string("string"),
                            "description": .string("Simulator device name to target (optional)")
                        ]),
                        "x": .object([
                            "type": .string("integer"),
                            "description": .string("X coordinate for tap/swipe start")
                        ]),
                        "y": .object([
                            "type": .string("integer"),
                            "description": .string("Y coordinate for tap/swipe start")
                        ]),
                        "to_x": .object([
                            "type": .string("integer"),
                            "description": .string("End X for swipe")
                        ]),
                        "to_y": .object([
                            "type": .string("integer"),
                            "description": .string("End Y for swipe")
                        ]),
                        "text": .object([
                            "type": .string("string"),
                            "description": .string("Text to type")
                        ]),
                        "button": .object([
                            "type": .string("string"),
                            "description": .string("Hardware button: home, lock, volumeUp, volumeDown"),
                            "enum": .array([.string("home"), .string("lock"), .string("volumeUp"), .string("volumeDown")])
                        ])
                    ]),
                    "required": .array([.string("action")])
                ])
            ),
            Tool(
                name: "simulator_find_text",
                description: """
                    Find text on the simulator screen and get its tap coordinates.

                    Use this to locate UI elements by their label text, then tap them with simulator_interact.

                    Example workflow:
                    1. simulator_find_text(text: "Login")
                    2. simulator_interact(action: "tap", x: result.x, y: result.y)
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "device_id": .object([
                            "type": .string("string"),
                            "description": .string("Simulator device UUID or 'booted' (default: booted)")
                        ]),
                        "text": .object([
                            "type": .string("string"),
                            "description": .string("Text to search for (case-insensitive partial match)")
                        ]),
                        "case_sensitive": .object([
                            "type": .string("boolean"),
                            "description": .string("Whether to match case exactly (default: false)")
                        ])
                    ]),
                    "required": .array([.string("text")])
                ])
            )
        ]
    }

    // MARK: - Tool Call Handler

    private func handleToolCall(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            switch params.name {
            case "simulator_ui_state":
                return try await handleSimulatorUIState(params.arguments)

            case "simulator_interact":
                return try await handleSimulatorInteract(params.arguments)

            case "simulator_find_text":
                return try await handleSimulatorFindText(params.arguments)

            default:
                return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
            }
        } catch {
            return .init(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    // MARK: - Tool Implementations

    private func handleSimulatorUIState(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        // Check accessibility permission first
        if !simulatorUIService.checkAccessibility() {
            simulatorUIService.requestAccessibility()
            return .init(content: [.text("""
                ## Accessibility Permission Required

                To interact with the simulator UI, grant Accessibility permission to your terminal app.

                **Steps:**
                1. Open System Settings > Privacy & Security > Accessibility
                2. Enable your terminal app (Terminal, iTerm2, etc.)
                3. Try again after granting permission
                """)], isError: true)
        }

        let deviceId = arguments?["device_id"]?.stringValue ?? "booted"

        // Take a screenshot first
        let screenshotResult = try await simulatorService.takeScreenshot(deviceId: deviceId, format: .png, mask: .ignored)
        let screenshotPath = screenshotResult.path

        // Get UI state with OCR
        let uiState = try await simulatorUIService.getUIState(screenshotPath: screenshotPath)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(uiState)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(uiState.summary + "\n\n```json\n\(jsonString)\n```")])
    }

    private func handleSimulatorInteract(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: action")], isError: true)
        }

        let deviceName = args["device_name"]?.stringValue
        let result: UIInteractionResult

        switch action {
        case "tap":
            guard let x = args["x"]?.intValue, let y = args["y"]?.intValue else {
                return .init(content: [.text("tap action requires x and y coordinates")], isError: true)
            }
            result = try await simulatorUIService.tap(x: x, y: y, deviceName: deviceName)

        case "swipe":
            guard let x = args["x"]?.intValue,
                  let y = args["y"]?.intValue,
                  let toX = args["to_x"]?.intValue,
                  let toY = args["to_y"]?.intValue else {
                return .init(content: [.text("swipe action requires x, y, to_x, and to_y coordinates")], isError: true)
            }
            let duration = args["duration"]?.doubleValue ?? 0.3
            result = try await simulatorUIService.swipe(fromX: x, fromY: y, toX: toX, toY: toY, duration: duration, deviceName: deviceName)

        case "type":
            guard let text = args["text"]?.stringValue else {
                return .init(content: [.text("type action requires text parameter")], isError: true)
            }
            result = try await simulatorUIService.typeText(text, deviceName: deviceName)

        case "button":
            guard let buttonStr = args["button"]?.stringValue else {
                return .init(content: [.text("button action requires button parameter")], isError: true)
            }
            guard let button = HardwareButton(rawValue: buttonStr) else {
                return .init(content: [.text("Unknown button: \(buttonStr). Valid: home, lock, volumeUp, volumeDown")], isError: true)
            }
            result = try await simulatorUIService.pressButton(button, deviceName: deviceName)

        default:
            return .init(content: [.text("Unknown action: \(action). Valid: tap, swipe, type, button")], isError: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return .init(content: [.text(result.summary + "\n\n```json\n\(jsonString)\n```")], isError: !result.success)
    }

    private func handleSimulatorFindText(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let searchText = args["text"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: text")], isError: true)
        }

        let deviceId = args["device_id"]?.stringValue ?? "booted"
        let caseSensitive = args["case_sensitive"]?.boolValue ?? false

        // Take a screenshot first
        let screenshotResult = try await simulatorService.takeScreenshot(deviceId: deviceId, format: .png, mask: .ignored)
        let screenshotPath = screenshotResult.path

        // Find the text
        if let found = try await simulatorUIService.findText(searchText, in: screenshotPath, caseSensitive: caseSensitive) {
            let response: [String: Any] = [
                "found": true,
                "text": found.text,
                "x": found.centerX,
                "y": found.centerY,
                "width": found.width,
                "height": found.height,
                "confidence": found.confidence
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            return .init(content: [.text("""
                ## Text Found: "\(found.text)"

                **Location:** (\(found.centerX), \(found.centerY)) - center point for tapping
                **Size:** \(found.width) × \(found.height) pixels
                **Confidence:** \(String(format: "%.1f%%", found.confidence * 100))

                **To tap this element:**
                ```
                simulator_interact(action: "tap", x: \(found.centerX), y: \(found.centerY))
                ```

                ```json
                \(jsonString)
                ```
                """)])
        } else {
            // Text not found - return all visible text to help
            let allText = try await simulatorUIService.recognizeText(in: screenshotPath)
            let visibleTexts = allText.prefix(15).map { "\"\($0.text)\"" }.joined(separator: ", ")

            return .init(content: [.text("""
                ## Text Not Found: "\(searchText)"

                The text was not found on screen.

                **Visible text on screen:**
                \(visibleTexts.isEmpty ? "No text detected" : visibleTexts)
                \(allText.count > 15 ? "\n... and \(allText.count - 15) more" : "")

                **Suggestions:**
                - Check spelling and case (case_sensitive: \(caseSensitive))
                - The text may be partially visible or obscured
                - Try scrolling to reveal more content
                - Use simulator_ui_state to see all text with coordinates
                """)], isError: true)
        }
    }
}
