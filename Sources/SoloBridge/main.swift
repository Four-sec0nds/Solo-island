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
func readExact(_ count: Int) throws -> Data {
    var data = Data()
    while data.count < count {
        let chunk = try FileHandle.standardInput.read(upToCount: count - data.count) ?? Data()
        if chunk.isEmpty { break }; data.append(chunk)
    }
    return data
}
func nativeMessage() throws {
    let header = try readExact(4)
    guard header.count == 4 else { return }
    let length = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32($1.offset * 8) }
    guard length > 0, length <= 4096 else { return }
    let bytes = try readExact(Int(length))
    var ok = false
    let mailbox = AgentMailbox(root: AgentMailbox.defaultRoot)
    if let heartbeat = mailbox.liveHeartbeat() {
        let event = try WebAgentEvent.decode(bytes).bridgeEvent(instance: heartbeat.instance, pid: getppid())
        try mailbox.write(event, to: mailbox.eventURL(event.id)); ok = true
    }
    let response = try JSONSerialization.data(withJSONObject: ["ok": ok])
    var size = UInt32(response.count).littleEndian
    try withUnsafeBytes(of: &size) { try FileHandle.standardOutput.write(contentsOf: Data($0)) }
    try FileHandle.standardOutput.write(contentsOf: response)
}
func hook(provider: AgentProvider) throws -> Data? {
    let mailbox = AgentMailbox(root: AgentMailbox.defaultRoot)
    guard let heartbeat = mailbox.liveHeartbeat() else { return nil }
    var input = Data()
    while input.count <= 512 * 1024 {
        let chunk = try FileHandle.standardInput.read(upToCount: min(8192, 512 * 1024 + 1 - input.count)) ?? Data()
        if chunk.isEmpty { break }; input.append(chunk)
    }
    let event = try AgentEvent(data: input, provider: provider, instance: heartbeat.instance, helperPID: getpid(), clientPID: getppid())
    return try AgentHookRunner.run(event, mailbox: mailbox, parentAlive: { getppid() != 1 })
}
if arguments.count >= 2 && arguments[1] == BrowserBridgeIdentity.origin { try? nativeMessage() }
else if arguments.count == 3, arguments[1] == "hook", let provider = AgentProvider(rawValue: arguments[2]),
        let output = try? hook(provider: provider) { try? FileHandle.standardOutput.write(contentsOf: output) }
