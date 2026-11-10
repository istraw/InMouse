import Foundation

enum ScriptActions {
    enum ScriptError: LocalizedError {
        case nonZeroExit(Int32, String)
        case appleScriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let code, let output):
                return "Shell exited \(code): \(output)"
            case .appleScriptFailed(let message):
                return message
            }
        }
    }

    static func runShell(_ command: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw ScriptError.nonZeroExit(process.terminationStatus, output)
        }
    }

    static func appleScriptString(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: ScriptError.appleScriptFailed(L10n.string("builtin.error.unavailable")))
                    return
                }
                let result = script.executeAndReturnError(&error)
                if let error {
                    continuation.resume(throwing: ScriptError.appleScriptFailed(
                        error[NSAppleScript.errorMessage] as? String ?? L10n.string("builtin.error.unavailable")))
                } else {
                    continuation.resume(returning: result.stringValue ?? "")
                }
            }
        }
    }

    static func runAppleScript(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                _ = script?.executeAndReturnError(&error)
                if let error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed"
                    continuation.resume(throwing: ScriptError.appleScriptFailed(message))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
