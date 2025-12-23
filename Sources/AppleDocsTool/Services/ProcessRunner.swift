import Foundation

/// Generic async process runner with timeout support
struct ProcessRunner {
    /// Configuration for running a process
    struct Configuration {
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
        let environment: [String: String]?
        let timeout: TimeInterval

        init(
            executable: String,
            arguments: [String] = [],
            workingDirectory: String? = nil,
            environment: [String: String]? = nil,
            timeout: TimeInterval = 300  // 5 minutes default
        ) {
            self.executable = executable
            self.arguments = arguments
            self.workingDirectory = workingDirectory
            self.environment = environment
            self.timeout = timeout
        }
    }

    /// Result of a process execution
    struct Result: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let duration: TimeInterval
        let wasTerminated: Bool
    }

    /// Error types for process execution
    enum ProcessError: Error, LocalizedError {
        case executableNotFound(String)
        case timeout(seconds: Int)
        case executionFailed(String)

        var errorDescription: String? {
            switch self {
            case .executableNotFound(let path):
                return "Executable not found: \(path)"
            case .timeout(let seconds):
                return "Process timed out after \(seconds) seconds"
            case .executionFailed(let message):
                return "Process execution failed: \(message)"
            }
        }
    }

    /// Run a process with the given configuration
    static func run(_ config: Configuration) async throws -> Result {
        let process = Process()

        // Set executable
        if config.executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: config.executable)
        } else {
            // Try to find in PATH
            process.executableURL = URL(fileURLWithPath: "/usr/bin/\(config.executable)")
        }

        process.arguments = config.arguments

        // Set working directory if specified
        if let workingDir = config.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        }

        // Set environment if specified
        if let env = config.environment {
            var processEnv = ProcessInfo.processInfo.environment
            for (key, value) in env {
                processEnv[key] = value
            }
            process.environment = processEnv
        }

        // Set up pipes for output capture
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Collect output asynchronously to avoid pipe buffer deadlock
        // (pipe buffer is ~64KB - if it fills, process blocks and never exits)
        final class LockedData: @unchecked Sendable {
            private var data = Data()
            private let lock = NSLock()

            func append(_ newData: Data) {
                lock.lock()
                data.append(newData)
                lock.unlock()
            }

            func get() -> Data {
                lock.lock()
                defer { lock.unlock() }
                return data
            }
        }

        let stdoutData = LockedData()
        let stderrData = LockedData()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutData.append(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrData.append(data)
            }
        }

        let startTime = Date()
        var wasTerminated = false

        do {
            try process.run()
        } catch {
            // Clean up handlers before throwing
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw ProcessError.executionFailed(error.localizedDescription)
        }

        // Wait with timeout using async polling
        while process.isRunning {
            if Date().timeIntervalSince(startTime) > config.timeout {
                process.terminate()
                wasTerminated = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        // Wait for process to fully terminate and close file descriptors
        // This is critical to prevent readDataToEndOfFile() from blocking indefinitely
        process.waitUntilExit()

        let duration = Date().timeIntervalSince(startTime)

        // Clean up readability handlers
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        // Read any remaining data in the pipes (now safe since process has fully exited)
        let remainingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let remainingError = errorPipe.fileHandleForReading.readDataToEndOfFile()

        // Combine all collected data
        var finalStdout = stdoutData.get()
        finalStdout.append(remainingOutput)
        var finalStderr = stderrData.get()
        finalStderr.append(remainingError)

        let stdout = String(data: finalStdout, encoding: .utf8) ?? ""
        let stderr = String(data: finalStderr, encoding: .utf8) ?? ""

        return Result(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            duration: duration,
            wasTerminated: wasTerminated
        )
    }

    /// Run swift command
    static func swift(
        arguments: [String],
        workingDirectory: String? = nil,
        timeout: TimeInterval = 300
    ) async throws -> Result {
        try await run(Configuration(
            executable: "/usr/bin/swift",
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeout: timeout
        ))
    }

    /// Run xcodebuild command
    static func xcodebuild(
        arguments: [String],
        workingDirectory: String? = nil,
        timeout: TimeInterval = 600
    ) async throws -> Result {
        try await run(Configuration(
            executable: "/usr/bin/xcodebuild",
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeout: timeout
        ))
    }

    /// Run xcrun command
    static func xcrun(
        arguments: [String],
        workingDirectory: String? = nil,
        timeout: TimeInterval = 60
    ) async throws -> Result {
        try await run(Configuration(
            executable: "/usr/bin/xcrun",
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeout: timeout
        ))
    }
}
