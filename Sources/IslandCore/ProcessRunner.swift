import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct CommandResult: Sendable {
    public var status: Int32
    public var output: Data
    public var error: String
}

public enum ProcessRunner {
    /// Drain both pipes while the process runs; neither output can deadlock the other.
    public static func run(_ executable: String, _ arguments: [String], timeout seconds: TimeInterval = 20) async throws -> CommandResult {
        try await Task.detached(priority: .utility) {
            try runSynchronously(executable, arguments, timeout: seconds)
        }.value
    }
    private static func runSynchronously(_ executable: String, _ arguments: [String], timeout seconds: TimeInterval) throws -> CommandResult {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe(), errors = Pipe()
            process.standardOutput = output; process.standardError = errors
            let group = DispatchGroup()
            let stdout = DataBox(), stderr = DataBox()
            try process.run()
            group.enter()
            DispatchQueue.global().async {
                stdout.value = output.fileHandleForReading.readDataToEndOfFile(); group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                stderr.value = errors.fileHandleForReading.readDataToEndOfFile(); group.leave()
            }
            // Local helpers should never hold the app indefinitely.
            let timeout = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + max(0.05, seconds), execute: timeout)
            process.waitUntilExit(); group.wait(); timeout.cancel()
            return CommandResult(status: process.terminationStatus, output: stdout.value,
                                 error: String(data: stderr.value, encoding: .utf8) ?? "")
    }
    private final class DataBox: @unchecked Sendable { var value = Data() }
}
