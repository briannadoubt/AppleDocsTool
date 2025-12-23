import Foundation
import CoreGraphics

// MARK: - Platform and State Enums

/// Simulator platform type
enum SimulatorPlatform: String, Codable, Sendable, CaseIterable {
    case iOS
    case watchOS
    case tvOS
    case visionOS

    /// Extract platform from runtime identifier
    static func from(runtimeIdentifier: String) -> SimulatorPlatform? {
        let id = runtimeIdentifier.lowercased()
        if id.contains("ios") { return .iOS }
        if id.contains("watchos") { return .watchOS }
        if id.contains("tvos") { return .tvOS }
        if id.contains("xros") || id.contains("visionos") { return .visionOS }
        return nil
    }
}

/// Device state
enum DeviceState: String, Codable, Sendable {
    case booted = "Booted"
    case shutdown = "Shutdown"
    case shuttingDown = "Shutting Down"
    case creating = "Creating"
    case unknown = "Unknown"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = DeviceState(rawValue: value) ?? .unknown
    }
}

// MARK: - Media Enums

/// Screenshot format
enum ScreenshotFormat: String, Codable, Sendable {
    case png
    case jpeg
    case tiff
    case bmp
    case gif
}

/// Video codec for recording
enum VideoCodec: String, Codable, Sendable {
    case h264
    case hevc
}

/// Display type for screenshots/recording
enum DisplayType: String, Codable, Sendable {
    case `internal`
    case external
}

/// Mask policy for screenshots
enum MaskPolicy: String, Codable, Sendable {
    case ignored
    case alpha
    case black
}

// MARK: - App Container Type

/// App container type
enum ContainerType: String, Codable, Sendable {
    case app
    case data
    case groups
    case shared = "group"
}

// MARK: - Privacy Service

/// Privacy service for permission control
enum PrivacyService: String, Codable, Sendable, CaseIterable {
    case all
    case calendar
    case contactsLimited = "contacts-limited"
    case contacts
    case location
    case locationAlways = "location-always"
    case photosAdd = "photos-add"
    case photos
    case mediaLibrary = "media-library"
    case microphone
    case motion
    case reminders
    case siri
    case camera
    case health
    case homekit
    case bluetooth = "bluetooth-peripheral"
    case speechRecognition = "speech-recognition"
    case userTracking = "user-tracking"
}

// MARK: - Device Types

/// Simulator device information
struct SimulatorDevice: Codable, Sendable {
    let udid: String
    let name: String
    let state: DeviceState
    let isAvailable: Bool
    let deviceTypeIdentifier: String?
    let dataPath: String?
    let logPath: String?
    let availabilityError: String?
    let lastBootedAt: String?

    enum CodingKeys: String, CodingKey {
        case udid
        case name
        case state
        case isAvailable
        case deviceTypeIdentifier
        case dataPath
        case logPath
        case availabilityError
        case lastBootedAt
    }
}

/// Simulator runtime information
struct SimulatorRuntime: Codable, Sendable {
    let identifier: String
    let name: String
    let version: String
    let buildversion: String
    let isAvailable: Bool
    let supportedDeviceTypes: [SupportedDeviceType]?

    var platform: SimulatorPlatform? {
        SimulatorPlatform.from(runtimeIdentifier: identifier)
    }
}

/// Supported device type within a runtime
struct SupportedDeviceType: Codable, Sendable {
    let identifier: String
    let name: String
    let productFamily: String?
}

/// Simulator device type
struct SimulatorDeviceType: Codable, Sendable {
    let identifier: String
    let name: String
    let productFamily: String?
    let modelIdentifier: String?
    let minRuntimeVersion: Int?
    let maxRuntimeVersion: Int?
}

// MARK: - Result Types

/// Result of listing simulators
struct SimulatorListResult: Codable, Sendable {
    let devices: [String: [SimulatorDevice]]
    let runtimes: [SimulatorRuntime]?

    var totalCount: Int {
        devices.values.reduce(0) { $0 + $1.count }
    }

    var bootedCount: Int {
        devices.values.reduce(0) { total, deviceList in
            total + deviceList.filter { $0.state == .booted }.count
        }
    }

    var availableCount: Int {
        devices.values.reduce(0) { total, deviceList in
            total + deviceList.filter { $0.isAvailable }.count
        }
    }

    var summary: String {
        "Found \(totalCount) devices (\(bootedCount) booted, \(availableCount) available)"
    }
}

/// Result of a simulator operation
struct SimulatorOperationResult: Codable, Sendable {
    let success: Bool
    let message: String
    let deviceId: String?
    let duration: TimeInterval?

    static func success(_ message: String, deviceId: String? = nil, duration: TimeInterval? = nil) -> SimulatorOperationResult {
        SimulatorOperationResult(success: true, message: message, deviceId: deviceId, duration: duration)
    }

    static func failure(_ message: String, deviceId: String? = nil) -> SimulatorOperationResult {
        SimulatorOperationResult(success: false, message: message, deviceId: deviceId, duration: nil)
    }
}

/// Result of launching an app
struct AppLaunchResult: Codable, Sendable {
    let success: Bool
    let pid: Int?
    let bundleId: String
    let deviceId: String
    let message: String?
}

/// Information about an installed app
struct AppInfo: Codable, Sendable {
    let bundleIdentifier: String
    let name: String?
    let version: String?
    let bundleVersion: String?
    let dataContainer: String?
    let bundlePath: String?
    let applicationType: String?
}

/// Simplified installed app info
struct InstalledApp: Codable, Sendable {
    let bundleIdentifier: String
    let name: String
    let version: String?
    let applicationType: String
}

// MARK: - Screenshot and Recording

/// Result of taking a screenshot
struct ScreenshotResult: Codable, Sendable {
    let path: String
    let format: ScreenshotFormat
    let deviceId: String
    let timestamp: Date

    var summary: String {
        "Screenshot saved to \(path)"
    }
}

/// Handle for an active recording
struct RecordingHandle: Codable, Sendable {
    let id: String
    let deviceId: String
    let outputPath: String
    let startTime: Date
    let codec: VideoCodec
}

/// Result of a completed recording
struct RecordingResult: Codable, Sendable {
    let path: String
    let duration: TimeInterval
    let deviceId: String
    let codec: VideoCodec
    let fileSize: Int64?

    var summary: String {
        let size = fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "unknown size"
        return "Recording saved to \(path) (\(String(format: "%.1f", duration))s, \(size))"
    }
}

// MARK: - Push Notification

/// Push notification payload
struct PushPayload: Codable, Sendable {
    let aps: APSPayload

    struct APSPayload: Codable, Sendable {
        let alert: AlertPayload?
        let badge: Int?
        let sound: String?
        let contentAvailable: Int?

        enum CodingKeys: String, CodingKey {
            case alert, badge, sound
            case contentAvailable = "content-available"
        }

        init(title: String? = nil, body: String? = nil, subtitle: String? = nil,
             badge: Int? = nil, sound: String? = nil, contentAvailable: Int? = nil) {
            if title != nil || body != nil || subtitle != nil {
                self.alert = AlertPayload(title: title, body: body, subtitle: subtitle)
            } else {
                self.alert = nil
            }
            self.badge = badge
            self.sound = sound
            self.contentAvailable = contentAvailable
        }
    }

    struct AlertPayload: Codable, Sendable {
        let title: String?
        let body: String?
        let subtitle: String?
    }

    init(title: String? = nil, body: String? = nil, subtitle: String? = nil,
         badge: Int? = nil, sound: String? = "default") {
        self.aps = APSPayload(title: title, body: body, subtitle: subtitle,
                              badge: badge, sound: sound)
    }
}

// MARK: - Status Bar Override

/// Status bar override settings
struct StatusBarOverrides: Codable, Sendable {
    var time: String?
    var dataNetwork: String?
    var wifiMode: String?
    var wifiBars: Int?
    var cellularMode: String?
    var cellularBars: Int?
    var operatorName: String?
    var batteryState: String?
    var batteryLevel: Int?

    func toArguments() -> [String] {
        var args: [String] = []
        if let time = time { args += ["--time", time] }
        if let dataNetwork = dataNetwork { args += ["--dataNetwork", dataNetwork] }
        if let wifiMode = wifiMode { args += ["--wifiMode", wifiMode] }
        if let wifiBars = wifiBars { args += ["--wifiBars", String(wifiBars)] }
        if let cellularMode = cellularMode { args += ["--cellularMode", cellularMode] }
        if let cellularBars = cellularBars { args += ["--cellularBars", String(cellularBars)] }
        if let operatorName = operatorName { args += ["--operatorName", operatorName] }
        if let batteryState = batteryState { args += ["--batteryState", batteryState] }
        if let batteryLevel = batteryLevel { args += ["--batteryLevel", String(batteryLevel)] }
        return args
    }
}

// MARK: - Location

/// Location waypoint for route simulation
struct LocationWaypoint: Codable, Sendable {
    let latitude: Double
    let longitude: Double

    var coordinateString: String {
        "\(latitude),\(longitude)"
    }
}

// MARK: - UI Interaction (Accessibility)

/// Hardware button for simulator
enum HardwareButton: String, Codable, Sendable {
    case home
    case lock
    case volumeUp
    case volumeDown
    case ringer  // Toggle silent mode
    case screenshot  // Cmd+S
    case keyboard  // Toggle software keyboard
}

/// Result of a UI interaction
struct UIInteractionResult: Codable, Sendable {
    let success: Bool
    let action: String
    let deviceName: String?
    let message: String?

    var summary: String {
        if success {
            return "Successfully performed \(action)" + (deviceName.map { " on \($0)" } ?? "")
        } else {
            return "Failed to perform \(action): \(message ?? "unknown error")"
        }
    }
}

/// Simulator window information for UI interaction
struct SimulatorWindow: Codable, Sendable {
    let deviceName: String
    let windowId: Int
    let bounds: CGRect
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case deviceName, windowId, isActive
        case boundsX, boundsY, boundsWidth, boundsHeight
    }

    init(deviceName: String, windowId: Int, bounds: CGRect, isActive: Bool) {
        self.deviceName = deviceName
        self.windowId = windowId
        self.bounds = bounds
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        windowId = try container.decode(Int.self, forKey: .windowId)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        let x = try container.decode(CGFloat.self, forKey: .boundsX)
        let y = try container.decode(CGFloat.self, forKey: .boundsY)
        let width = try container.decode(CGFloat.self, forKey: .boundsWidth)
        let height = try container.decode(CGFloat.self, forKey: .boundsHeight)
        bounds = CGRect(x: x, y: y, width: width, height: height)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(windowId, forKey: .windowId)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(bounds.origin.x, forKey: .boundsX)
        try container.encode(bounds.origin.y, forKey: .boundsY)
        try container.encode(bounds.size.width, forKey: .boundsWidth)
        try container.encode(bounds.size.height, forKey: .boundsHeight)
    }
}
