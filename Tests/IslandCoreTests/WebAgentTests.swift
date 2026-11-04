import XCTest
@testable import IslandCore

final class WebAgentTests: XCTestCase {
    func payload(_ state: String, host: String = "chatgpt.com", provider: String = "codex", extra: Bool = false) throws -> Data {
        var value: [String: Any] = ["provider": provider, "host": host, "session": "A25F8B42-7C90-4DA8-83B7-4C4033A70210", "state": state]
        if extra { value["prompt"] = "must not enter the bridge" }
        return try JSONSerialization.data(withJSONObject: value)
    }
    func testWebLifecycleKeepsTheStartTimeAndStopsWithoutAClientPID() throws {
        let instance = UUID(), start = Date(timeIntervalSince1970: 1000)
        var activity = AgentActivity()
        activity.ingest(try WebAgentEvent.decode(payload("start")).bridgeEvent(instance: instance, pid: 999, at: start))
        activity.ingest(try WebAgentEvent.decode(payload("working")).bridgeEvent(instance: instance, pid: 999, at: start.addingTimeInterval(30)))
        activity.expire(at: start.addingTimeInterval(50), clientAlive: { _ in false }) { _ in true }
        XCTAssertEqual(activity.current?.elapsed(at: start.addingTimeInterval(50)), 50)
        XCTAssertTrue(activity.current?.isWeb == true)
        activity.ingest(try WebAgentEvent.decode(payload("finished")).bridgeEvent(instance: instance, pid: 999, at: start.addingTimeInterval(70)))
        XCTAssertNil(activity.current)
        XCTAssertEqual(activity.sessions[0].elapsed(at: start.addingTimeInterval(600)), 70)
    }
    func testInvalidHostsUnexpectedDataAndWebApprovalsAreRejected() throws {
        for data in [try payload("start", host: "chatgpt.com.evil.test"), try payload("start", host: "claude.ai"),
                     try payload("PermissionRequest"), try payload("start", extra: true)] {
            XCTAssertThrowsError(try WebAgentEvent.decode(data))
        }
        let event = try WebAgentEvent.decode(payload("start", host: "claude.ai", provider: "claude"))
        let bridge = try event.bridgeEvent(instance: UUID(), pid: 1)
        XCTAssertTrue(bridge.isWeb); XCTAssertNil(bridge.input); XCTAssertEqual(bridge.cwd, "claude.ai")
    }
    func testMissingBrowserHeartbeatsDoNotLeaveAForeverRunningTimer() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var activity = AgentActivity()
        activity.ingest(try WebAgentEvent.decode(payload("start")).bridgeEvent(instance: UUID(), pid: 1, at: start))
        activity.expire(at: start.addingTimeInterval(121)) { _ in true }
        XCTAssertNil(activity.current); XCTAssertEqual(activity.sessions[0].status, .unknown)
    }
    func testPaginationPreservesEveryItemAtAllCapacities() {
        for total in [0, 1, 9, 100] {
            for capacity in [1, 2, 6] {
                let pages = ContentPages.count(items: total, capacity: capacity)
                let values = (0..<pages).flatMap { Array(ContentPages.range(items: total, capacity: capacity, page: $0)) }
                XCTAssertEqual(values, Array(0..<total))
                XCTAssertTrue(ContentPages.range(items: total, capacity: capacity, page: 999).upperBound <= total)
            }
        }
    }
}
