import Foundation
import AppleDocsToolCore

let server = AppleDocsToolServer()

Task {
    do {
        try await server.start()
    } catch {
        fputs("Error starting server: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

RunLoop.main.run()
