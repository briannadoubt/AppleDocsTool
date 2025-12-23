import Foundation

/// Service for controlling iOS, watchOS, tvOS, and visionOS simulators via simctl
actor SimulatorService {
    private let fileManager = FileManager.default

    // Track active video recordings
    private var activeRecordings: [String: Process] = [:]

    // MARK: - Error Types

    enum SimulatorError: Error, LocalizedError {
        case deviceNotFound(String)
        case runtimeNotFound(String)
        case deviceTypeNotFound(String)
        case appNotInstalled(String)
        case operationFailed(String)
        case invalidPayload(String)
        case bootFailed(String)
        case recordingFailed(String)
        case recordingNotFound(String)
        case permissionDenied(String)

        var errorDescription: String? {
            switch self {
            case .deviceNotFound(let id): return "Device not found: \(id)"
            case .runtimeNotFound(let id): return "Runtime not found: \(id)"
            case .deviceTypeNotFound(let id): return "Device type not found: \(id)"
            case .appNotInstalled(let bundle): return "App not installed: \(bundle)"
            case .operationFailed(let msg): return "Operation failed: \(msg)"
            case .invalidPayload(let msg): return "Invalid payload: \(msg)"
            case .bootFailed(let msg): return "Boot failed: \(msg)"
            case .recordingFailed(let msg): return "Recording failed: \(msg)"
            case .recordingNotFound(let id): return "Recording not found: \(id)"
            case .permissionDenied(let msg): return "Permission denied: \(msg)"
            }
        }
    }

    // MARK: - Device Listing

    /// List all simulator devices with optional filtering
    func listDevices(
        platform: SimulatorPlatform? = nil,
        state: DeviceState? = nil,
        availableOnly: Bool = true
    ) async throws -> SimulatorListResult {
        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "list", "devices", "--json"],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        var listResult = try OutputParser.parseSimulatorList(result.stdout)

        // Apply filters
        if platform != nil || state != nil || availableOnly {
            var filteredDevices: [String: [SimulatorDevice]] = [:]

            for (runtimeId, devices) in listResult.devices {
                let runtimePlatform = SimulatorPlatform.from(runtimeIdentifier: runtimeId)

                // Filter by platform
                if let platform = platform, runtimePlatform != platform {
                    continue
                }

                let filtered = devices.filter { device in
                    // Filter by state
                    if let state = state, device.state != state {
                        return false
                    }
                    // Filter by availability
                    if availableOnly && !device.isAvailable {
                        return false
                    }
                    return true
                }

                if !filtered.isEmpty {
                    filteredDevices[runtimeId] = filtered
                }
            }

            listResult = SimulatorListResult(devices: filteredDevices, runtimes: listResult.runtimes)
        }

        return listResult
    }

    /// List available runtimes
    func listRuntimes() async throws -> [SimulatorRuntime] {
        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "list", "runtimes", "--json"],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return try OutputParser.parseSimulatorRuntimes(result.stdout)
    }

    /// List available device types
    func listDeviceTypes() async throws -> [SimulatorDeviceType] {
        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "list", "devicetypes", "--json"],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return try OutputParser.parseSimulatorDeviceTypes(result.stdout)
    }

    // MARK: - Device Control

    /// Boot a simulator device
    func bootDevice(_ deviceId: String) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)
        let startTime = Date()

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "boot", resolvedId],
            timeout: 120
        )

        let duration = Date().timeIntervalSince(startTime)

        if result.exitCode != 0 {
            // Check if already booted
            if result.stderr.contains("Unable to boot device in current state: Booted") {
                return .success("Device already booted", deviceId: resolvedId, duration: duration)
            }
            throw SimulatorError.bootFailed(result.stderr)
        }

        return .success("Device booted successfully", deviceId: resolvedId, duration: duration)
    }

    /// Shutdown a simulator device
    func shutdownDevice(_ deviceId: String) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)
        let startTime = Date()

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "shutdown", resolvedId],
            timeout: 60
        )

        let duration = Date().timeIntervalSince(startTime)

        if result.exitCode != 0 {
            if result.stderr.contains("Unable to shutdown device in current state: Shutdown") {
                return .success("Device already shutdown", deviceId: resolvedId, duration: duration)
            }
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("Device shutdown successfully", deviceId: resolvedId, duration: duration)
    }

    /// Create a new simulator device
    func createDevice(
        name: String,
        deviceTypeId: String,
        runtimeId: String? = nil
    ) async throws -> SimulatorDevice {
        // Resolve device type
        let deviceTypes = try await listDeviceTypes()
        let matchedType = deviceTypes.first {
            $0.identifier == deviceTypeId ||
            $0.name.lowercased() == deviceTypeId.lowercased() ||
            $0.name.lowercased().contains(deviceTypeId.lowercased())
        }

        guard let deviceType = matchedType else {
            throw SimulatorError.deviceTypeNotFound(deviceTypeId)
        }

        // Resolve runtime
        let runtimes = try await listRuntimes()
        let matchedRuntime: SimulatorRuntime?

        if let runtimeId = runtimeId {
            matchedRuntime = runtimes.first {
                $0.identifier == runtimeId ||
                $0.name.lowercased() == runtimeId.lowercased() ||
                $0.name.lowercased().contains(runtimeId.lowercased())
            }
        } else {
            // Use latest available runtime for the device's platform
            matchedRuntime = runtimes
                .filter { $0.isAvailable }
                .sorted { $0.version > $1.version }
                .first
        }

        guard let runtime = matchedRuntime else {
            throw SimulatorError.runtimeNotFound(runtimeId ?? "latest")
        }

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "create", name, deviceType.identifier, runtime.identifier],
            timeout: 60
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        // The output is just the UDID
        let udid = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        return SimulatorDevice(
            udid: udid,
            name: name,
            state: .shutdown,
            isAvailable: true,
            deviceTypeIdentifier: deviceType.identifier,
            dataPath: nil,
            logPath: nil,
            availabilityError: nil,
            lastBootedAt: nil
        )
    }

    /// Delete a simulator device
    func deleteDevice(_ deviceId: String) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "delete", resolvedId],
            timeout: 60
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("Device deleted successfully", deviceId: resolvedId)
    }

    /// Erase a simulator device (reset to clean state)
    func eraseDevice(_ deviceId: String) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "erase", resolvedId],
            timeout: 120
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("Device erased successfully", deviceId: resolvedId)
    }

    /// Clone an existing device
    func cloneDevice(_ deviceId: String, name: String) async throws -> SimulatorDevice {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "clone", resolvedId, name],
            timeout: 120
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        let udid = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        return SimulatorDevice(
            udid: udid,
            name: name,
            state: .shutdown,
            isAvailable: true,
            deviceTypeIdentifier: nil,
            dataPath: nil,
            logPath: nil,
            availabilityError: nil,
            lastBootedAt: nil
        )
    }

    // MARK: - App Management

    /// Install an app on a device
    func installApp(deviceId: String, appPath: String) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        guard fileManager.fileExists(atPath: appPath) else {
            throw SimulatorError.operationFailed("App not found at path: \(appPath)")
        }

        let startTime = Date()
        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "install", resolvedId, appPath],
            timeout: 120
        )
        let duration = Date().timeIntervalSince(startTime)

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("App installed successfully", deviceId: resolvedId, duration: duration)
    }

    /// Uninstall an app from a device
    func uninstallApp(deviceId: String, bundleId: String) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "uninstall", resolvedId, bundleId],
            timeout: 60
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("App uninstalled successfully", deviceId: resolvedId)
    }

    /// Launch an app on a device
    func launchApp(
        deviceId: String,
        bundleId: String,
        arguments: [String]? = nil,
        environment: [String: String]? = nil,
        waitForDebugger: Bool = false
    ) async throws -> AppLaunchResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        var args = ["simctl", "launch"]

        if waitForDebugger {
            args.append("--wait-for-debugger")
        }

        // Add environment variables via SIMCTL_CHILD_ prefix
        var env = ProcessInfo.processInfo.environment
        if let environment = environment {
            for (key, value) in environment {
                env["SIMCTL_CHILD_\(key)"] = value
            }
        }

        args.append(resolvedId)
        args.append(bundleId)

        if let arguments = arguments {
            args.append(contentsOf: arguments)
        }

        let result = try await ProcessRunner.run(ProcessRunner.Configuration(
            executable: "/usr/bin/xcrun",
            arguments: args,
            environment: env,
            timeout: 60
        ))

        if result.exitCode != 0 {
            return AppLaunchResult(
                success: false,
                pid: nil,
                bundleId: bundleId,
                deviceId: resolvedId,
                message: result.stderr
            )
        }

        let pid = OutputParser.parseLaunchPID(result.stdout)

        return AppLaunchResult(
            success: true,
            pid: pid,
            bundleId: bundleId,
            deviceId: resolvedId,
            message: nil
        )
    }

    /// Terminate a running app
    func terminateApp(deviceId: String, bundleId: String) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "terminate", resolvedId, bundleId],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("App terminated successfully", deviceId: resolvedId)
    }

    /// Get information about an installed app
    func getAppInfo(deviceId: String, bundleId: String) async throws -> AppInfo {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "appinfo", resolvedId, bundleId],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.appNotInstalled(bundleId)
        }

        guard let appInfo = OutputParser.parseAppInfo(result.stdout) else {
            throw SimulatorError.operationFailed("Failed to parse app info")
        }

        return appInfo
    }

    /// List all installed apps on a device
    func listApps(deviceId: String) async throws -> [InstalledApp] {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "listapps", resolvedId],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return try OutputParser.parseInstalledApps(result.stdout)
    }

    /// Get app container path
    func getAppContainer(
        deviceId: String,
        bundleId: String,
        containerType: ContainerType? = nil
    ) async throws -> String {
        let resolvedId = try await resolveDeviceId(deviceId)

        var args = ["simctl", "get_app_container", resolvedId, bundleId]
        if let containerType = containerType {
            args.append(containerType.rawValue)
        }

        let result = try await ProcessRunner.xcrun(arguments: args, timeout: 30)

        if result.exitCode != 0 {
            throw SimulatorError.appNotInstalled(bundleId)
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Screenshot and Recording

    /// Take a screenshot of a device
    func takeScreenshot(
        deviceId: String,
        outputPath: String? = nil,
        format: ScreenshotFormat = .png,
        display: DisplayType = .internal,
        mask: MaskPolicy = .black
    ) async throws -> ScreenshotResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        let path = outputPath ?? fileManager.temporaryDirectory
            .appendingPathComponent("screenshot_\(UUID().uuidString.prefix(8)).\(format.rawValue)")
            .path

        var args = ["simctl", "io", resolvedId, "screenshot"]
        args.append("--type=\(format.rawValue)")
        args.append("--display=\(display.rawValue)")
        args.append("--mask=\(mask.rawValue)")
        args.append(path)

        let result = try await ProcessRunner.xcrun(arguments: args, timeout: 30)

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return ScreenshotResult(
            path: path,
            format: format,
            deviceId: resolvedId,
            timestamp: Date()
        )
    }

    /// Start recording video from a device
    func startRecording(
        deviceId: String,
        outputPath: String? = nil,
        codec: VideoCodec = .hevc
    ) async throws -> RecordingHandle {
        let resolvedId = try await resolveDeviceId(deviceId)

        let path = outputPath ?? fileManager.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString.prefix(8)).mov")
            .path

        let handleId = UUID().uuidString

        // Create and start process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "simctl", "io", resolvedId, "recordVideo",
            "--codec=\(codec.rawValue)",
            path
        ]

        // Suppress output
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()

        // Store the process
        activeRecordings[handleId] = process

        return RecordingHandle(
            id: handleId,
            deviceId: resolvedId,
            outputPath: path,
            startTime: Date(),
            codec: codec
        )
    }

    /// Stop a video recording
    func stopRecording(_ handle: RecordingHandle) async throws -> RecordingResult {
        guard let process = activeRecordings[handle.id] else {
            throw SimulatorError.recordingNotFound(handle.id)
        }

        // Send SIGINT to stop recording gracefully
        process.interrupt()

        // Wait for process to finish
        process.waitUntilExit()

        // Remove from active recordings
        activeRecordings.removeValue(forKey: handle.id)

        let duration = Date().timeIntervalSince(handle.startTime)

        // Get file size
        var fileSize: Int64?
        if let attrs = try? fileManager.attributesOfItem(atPath: handle.outputPath) {
            fileSize = attrs[.size] as? Int64
        }

        return RecordingResult(
            path: handle.outputPath,
            duration: duration,
            deviceId: handle.deviceId,
            codec: handle.codec,
            fileSize: fileSize
        )
    }

    // MARK: - Location Simulation

    /// Set a fixed location on a device
    func setLocation(deviceId: String, latitude: Double, longitude: Double) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "location", resolvedId, "set", "\(latitude),\(longitude)"],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("Location set to \(latitude),\(longitude)", deviceId: resolvedId)
    }

    /// Clear simulated location
    func clearLocation(deviceId: String) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "location", resolvedId, "clear"],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("Location cleared", deviceId: resolvedId)
    }

    /// Start a location route simulation
    func startLocationRoute(
        deviceId: String,
        waypoints: [LocationWaypoint],
        speed: Double? = nil
    ) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        guard waypoints.count >= 2 else {
            throw SimulatorError.invalidPayload("At least 2 waypoints required for a route")
        }

        var args = ["simctl", "location", resolvedId, "start"]

        if let speed = speed {
            args.append("--speed=\(speed)")
        }

        args.append(contentsOf: waypoints.map { $0.coordinateString })

        let result = try await ProcessRunner.xcrun(arguments: args, timeout: 30)

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("Location route started with \(waypoints.count) waypoints", deviceId: resolvedId)
    }

    // MARK: - Push Notifications

    /// Send a push notification to a device
    func sendPushNotification(
        deviceId: String,
        bundleId: String,
        payload: PushPayload
    ) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        // Write payload to temp file
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let jsonData = try encoder.encode(payload)

        let tempFile = fileManager.temporaryDirectory
            .appendingPathComponent("push_\(UUID().uuidString.prefix(8)).json")

        try jsonData.write(to: tempFile)

        defer {
            try? fileManager.removeItem(at: tempFile)
        }

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "push", resolvedId, bundleId, tempFile.path],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("Push notification sent", deviceId: resolvedId)
    }

    // MARK: - Privacy/Permissions

    /// Grant a permission to an app
    func grantPermission(
        deviceId: String,
        bundleId: String,
        service: PrivacyService
    ) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "privacy", resolvedId, "grant", service.rawValue, bundleId],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("Permission '\(service.rawValue)' granted to \(bundleId)", deviceId: resolvedId)
    }

    /// Revoke a permission from an app
    func revokePermission(
        deviceId: String,
        bundleId: String,
        service: PrivacyService
    ) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "privacy", resolvedId, "revoke", service.rawValue, bundleId],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("Permission '\(service.rawValue)' revoked from \(bundleId)", deviceId: resolvedId)
    }

    /// Reset permissions for an app or all apps
    func resetPermissions(
        deviceId: String,
        service: PrivacyService,
        bundleId: String? = nil
    ) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        var args = ["simctl", "privacy", resolvedId, "reset", service.rawValue]
        if let bundleId = bundleId {
            args.append(bundleId)
        }

        let result = try await ProcessRunner.xcrun(arguments: args, timeout: 30)

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        let target = bundleId ?? "all apps"
        return .success("Permission '\(service.rawValue)' reset for \(target)", deviceId: resolvedId)
    }

    // MARK: - Status Bar

    /// Override status bar appearance
    func setStatusBar(deviceId: String, overrides: StatusBarOverrides) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        var args = ["simctl", "status_bar", resolvedId, "override"]
        args.append(contentsOf: overrides.toArguments())

        let result = try await ProcessRunner.xcrun(arguments: args, timeout: 30)

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("Status bar overridden", deviceId: resolvedId)
    }

    /// Clear status bar overrides
    func clearStatusBar(deviceId: String) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "status_bar", resolvedId, "clear"],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("Status bar cleared", deviceId: resolvedId)
    }

    // MARK: - Pasteboard

    /// Set pasteboard (clipboard) content
    func setPasteboard(deviceId: String, content: String) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        // pbcopy reads from stdin
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "pbcopy", resolvedId]

        let inputPipe = Pipe()
        process.standardInput = inputPipe

        try process.run()

        inputPipe.fileHandleForWriting.write(content.data(using: .utf8)!)
        inputPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw SimulatorError.operationFailed("Failed to set pasteboard")
        }

        return .success("Pasteboard content set", deviceId: resolvedId)
    }

    /// Get pasteboard (clipboard) content
    func getPasteboard(deviceId: String) async throws -> String {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "pbpaste", resolvedId],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return result.stdout
    }

    // MARK: - URL Opening

    /// Open a URL on a device (for deep linking)
    func openURL(deviceId: String, url: String) async throws -> SimulatorOperationResult {
        let resolvedId = try await resolveDeviceId(deviceId)

        let result = try await ProcessRunner.xcrun(
            arguments: ["simctl", "openurl", resolvedId, url],
            timeout: 30
        )

        if result.exitCode != 0 {
            throw SimulatorError.operationFailed(result.stderr)
        }

        return .success("URL opened: \(url)", deviceId: resolvedId)
    }

    // MARK: - Helper Methods

    /// Resolve a device identifier (UDID, name, or "booted")
    private func resolveDeviceId(_ deviceIdOrName: String) async throws -> String {
        // "booted" is a special keyword
        if deviceIdOrName.lowercased() == "booted" {
            return "booted"
        }

        // Check if it looks like a UDID (contains dashes and is long enough)
        if deviceIdOrName.contains("-") && deviceIdOrName.count >= 36 {
            return deviceIdOrName
        }

        // Search by name
        let devices = try await listDevices(availableOnly: false)

        for (_, deviceList) in devices.devices {
            if let device = deviceList.first(where: {
                $0.name.lowercased() == deviceIdOrName.lowercased() ||
                $0.name.lowercased().contains(deviceIdOrName.lowercased())
            }) {
                return device.udid
            }
        }

        throw SimulatorError.deviceNotFound(deviceIdOrName)
    }
}
