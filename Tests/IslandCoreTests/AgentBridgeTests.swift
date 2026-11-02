import XCTest
@testable import IslandCore

final class AgentBridgeTests: XCTestCase {
    let instance = UUID()
    func event(_ hook: AgentHook, provider: AgentProvider = .codex, at date: Date = Date(), lifetime: TimeInterval = 120) throws -> AgentEvent {
        let data = try JSONSerialization.data(withJSONObject: ["session_id": "session-1", "hook_event_name": hook.rawValue,
            "cwd": "/Projects/Solo", "tool_name": "Bash", "tool_input": ["command": "swift test"],
            "prompt": "PRIVATE PROMPT", "transcript_path": "/private/transcript"])
        return try AgentEvent(data: data, provider: provider, instance: instance,
            helperPID: ProcessInfo.processInfo.processIdentifier, now: date, lifetime: lifetime)
    }
    func mailbox() throws -> AgentMailbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("solo-agent-test-" + UUID().uuidString)
        let mailbox = AgentMailbox(root: root); try mailbox.prepare()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try mailbox.write(AgentHeartbeat(instance: instance, pid: ProcessInfo.processInfo.processIdentifier), to: mailbox.heartbeatURL)
        return mailbox
    }
    func testTurnClockStopsRestartsAndSeparatesProviders() throws {
        let date = Date(timeIntervalSince1970: 1000)
        var activity = AgentActivity()
        activity.ingest(try event(.prompt, at: date))
        activity.ingest(try event(.preTool, at: date.addingTimeInterval(100)))
        activity.ingest(try event(.stop, at: date.addingTimeInterval(150)))
        XCTAssertEqual(activity.sessions[0].elapsed(at: date.addingTimeInterval(999)), 150)
        XCTAssertEqual(activity.sessions[0].clock(at: date.addingTimeInterval(999)), "00:02")
        activity.ingest(try event(.prompt, at: date.addingTimeInterval(200)))
        XCTAssertEqual(activity.current?.elapsed(at: date.addingTimeInterval(210)), 10)
        activity.ingest(try event(.prompt, provider: .claude, at: date.addingTimeInterval(201)))
        XCTAssertEqual(activity.sessions.count, 2)
        activity.ingest(try event(.stop, at: date)) // Delayed older event cannot end a newer turn.
        XCTAssertEqual(activity.sessions.first { $0.provider == .codex }?.status, .working)
    }
    func testParallelApprovalsResolveIndividuallyAndExpire() throws {
        var activity = AgentActivity()
        let first = try event(.permission), second = try event(.permission)
        activity.ingest(first); activity.ingest(second)
        XCTAssertEqual(activity.pending.count, 2)
        activity.resolved(first.id, at: Date())
        XCTAssertEqual(activity.current?.status, .waiting)
        XCTAssertEqual(activity.pending.map(\.id), [second.id])
        activity.expire(at: second.expiresAt) { _ in true }
        XCTAssertTrue(activity.pending.isEmpty)
        XCTAssertNil(activity.current)
    }
    func testInputMinimisationAndInvalidPayloads() throws {
        let ordinary = try event(.preTool)
        XCTAssertNil(ordinary.input)
        let encoded = String(decoding: try JSONEncoder().encode(ordinary), as: UTF8.self)
        XCTAssertFalse(encoded.contains("PRIVATE PROMPT")); XCTAssertFalse(encoded.contains("transcript"))
        XCTAssertTrue(try event(.permission).input?.contains("swift test") == true)
        for bytes in [Data("{}".utf8), Data(repeating: 32, count: 512 * 1024 + 1)] {
            XCTAssertThrowsError(try AgentEvent(data: bytes, provider: .codex, instance: instance, helperPID: 1))
        }
    }
    func testConfigMergeIsIdempotentAndPreservesOtherHooksAndSettings() throws {
        let original = Data(#"{"model":"keep","hooks":{"PermissionRequest":[{"matcher":"Bash","hooks":[{"type":"command","command":"other-check"}]}]}}"#.utf8)
        for provider in AgentProvider.allCases {
            let path = "/Users/O'Neil/Library/Application Support/SoloIsland/AgentBridge/SoloBridge"
            let once = try AgentHookConfiguration.merging(original, provider: provider, helper: path, enabled: true)
            XCTAssertTrue(AgentHookConfiguration.isEnabled(once, provider: provider, helper: path))
            XCTAssertEqual(once, try AgentHookConfiguration.merging(once, provider: provider, helper: path, enabled: true))
            let disabled = try AgentHookConfiguration.merging(once, provider: provider, helper: path, enabled: false)
            XCTAssertFalse(AgentHookConfiguration.isEnabled(disabled, provider: provider, helper: path))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: disabled) as? [String: Any])
            XCTAssertEqual(root["model"] as? String, "keep")
            XCTAssertTrue(String(decoding: disabled, as: UTF8.self).contains("other-check"))
            XCTAssertTrue(AgentHookConfiguration.command(helper: path, provider: provider).contains("'\\''"))
        }
        XCTAssertThrowsError(try AgentHookConfiguration.merging(Data("[]".utf8), provider: .codex, helper: "/x", enabled: true))
    }
    func testAllowDenyAndNativePromptRoundTripWithoutReplays() throws {
        for decision in [AgentDecision.allow, .deny, .client] {
            let box = try mailbox(), request = try event(.permission)
            var replied = false
            let output = try AgentHookRunner.run(request, mailbox: box, pause: {
                guard !replied else { return }; replied = true
                do { try box.respond(to: request, instance: self.instance, decision: decision) }
                catch { XCTFail("Live response failed: \(error)") }
                do {
                    try box.respond(to: request, instance: self.instance, decision: .allow)
                    XCTFail("A request must not accept a second decision")
                } catch { /* Expected single-use rejection. */ }
            })
            XCTAssertTrue(replied)
            XCTAssertFalse(FileManager.default.fileExists(atPath: box.eventURL(request.id).path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: box.replyURL(request.id).path))
            if decision == .client { XCTAssertEqual(output, Data()) }
            else {
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(output)) as? [String: Any])
                let specific = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
                XCTAssertEqual(specific["hookEventName"] as? String, "PermissionRequest")
                XCTAssertEqual((specific["decision"] as? [String: Any])?["behavior"] as? String, decision.rawValue)
            }
        }
    }
    func testExitTimeoutAndMismatchedRepliesNeverGrantPermission() throws {
        let box = try mailbox(), request = try event(.permission, lifetime: 0.05)
        let wrong = AgentReply(instance: UUID(), request: request.id, decision: .allow)
        try box.write(wrong, to: box.replyURL(request.id))
        XCTAssertNil(try AgentHookRunner.run(request, mailbox: box))
        XCTAssertThrowsError(try box.respond(to: request, instance: instance, decision: .allow))
        let live = try event(.permission)
        XCTAssertNil(try AgentHookRunner.run(live, mailbox: box, parentAlive: { false }))
        XCTAssertNil(try AgentHookRunner.run(live, mailbox: box, pause: { try? FileManager.default.removeItem(at: box.heartbeatURL) }))
    }
    func testPrivatePermissionsAndSymlinkRejection() throws {
        let box = try mailbox(), request = try event(.permission)
        try box.write(request, to: box.eventURL(request.id))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: box.root.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: box.eventURL(request.id).path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let link = box.root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: box.eventURL(request.id))
        XCTAssertThrowsError(try box.read(AgentEvent.self, from: link))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: box.eventURL(request.id).path)
        XCTAssertThrowsError(try box.read(AgentEvent.self, from: box.eventURL(request.id)))
    }
    func testPermissionIndicatorTakesPriorityOverFocusThenReturns() throws {
        var activity = AgentActivity(); let request = try event(.permission)
        activity.ingest(request)
        let focus = FocusSession(taskID: UUID(), minutes: 25)
        XCTAssertEqual(NotchActivity(track: NowPlaying(), focus: focus, agent: activity.current), .agent(.codex, waiting: true))
        activity.resolved(request.id, at: Date())
        XCTAssertEqual(NotchActivity(track: NowPlaying(), focus: focus, agent: activity.current), .focus(paused: false, music: nil))
        XCTAssertEqual(NotchActivity(track: NowPlaying(), focus: nil, agent: activity.current), .agent(.codex, waiting: false))
    }
}
