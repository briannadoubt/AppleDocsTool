import Foundation
import MCP

// Use minimal server by default (skills-based approach)
// Pass --full for all 30+ tools
let useMinimal = !CommandLine.arguments.contains("--full")

Task {
    do {
        if useMinimal {
            let server = MinimalMCPServer()
            try await server.start()
        } else {
            let server = AppleDocsToolServer()
            try await server.start()
        }
    } catch {
        fputs("Error starting server: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

RunLoop.main.run()
