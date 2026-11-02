import Foundation
import IslandCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Hook stdout is a protocol channel. Failure, absent app and timeout all exit
// successfully without a verdict, preserving the client's own approval flow.
let arguments = CommandLine.arguments
guard arguments.count == 3, arguments[1] == "hook", let provider = AgentProvider(rawValue: arguments[2]) else { exit(0) }
func run(provider: AgentProvider) throws -> Data? {
    let mailbox = AgentMailbox(root: AgentMailbox.defaultRoot)
    guard let heartbeat = mailbox.liveHeartbeat() else { return nil }
    var input = Data()
    while input.count <= 512 * 1024 {
        let chunk = try FileHandle.standardInput.read(upToCount: min(8192, 512 * 1024 + 1 - input.count)) ?? Data()
        if chunk.isEmpty { break }; input.append(chunk)
    }
    let event = try AgentEvent(data: input, provider: provider, instance: heartbeat.instance, helperPID: getpid())
    return try AgentHookRunner.run(event, mailbox: mailbox, parentAlive: { getppid() != 1 })
}
if let output = try? run(provider: provider) { try? FileHandle.standardOutput.write(contentsOf: output) }
