import Foundation
import Testing
@testable import CompanionCore

@Test func submitReusesOperationId() async throws {
    let bodies = LockedBox<[String]>([])
    let transport = ScriptedHTTPTransport { call in
        if let body = call.body, let text = String(data: body, encoding: .utf8) {
            bodies.append(text)
        }
        return HTTPExchange(status: 200, body: Data(#"{"data":{}}"#.utf8))
    }
    let client = HostClient(transport: transport)
    let origin = try HostOrigin.parse("http://10.0.0.2:3080")
    let op = "op-stable"
    try await client.submitInput(origin: origin, token: "t", operationId: op, conversationId: "c", agentId: "grok", workspaceId: "w", text: "hi")
    try await client.submitInput(origin: origin, token: "t", operationId: op, conversationId: "c", agentId: "grok", workspaceId: "w", text: "hi")
    #expect(bodies.items.count == 2)
    #expect(bodies.items[0].contains("op-stable"))
    #expect(bodies.items[1].contains("op-stable"))
}

@Test func redeemRejectsExtraScopes() async throws {
    let transport = ScriptedHTTPTransport { call in
        if call.url.contains("redeem") {
            let body = #"{"device_id":"d1","access_token":"tok","scopes":["conversation.read","plugin.write"]}"#
            return HTTPExchange(status: 200, body: Data(body.utf8))
        }
        return HTTPExchange(status: 500, body: Data())
    }
    do {
        _ = try await PairingClient(transport: transport).redeem(
            origin: try HostOrigin.parse("http://10.0.0.2:3080"),
            pairingToken: "ABCD1234"
        )
        Issue.record("expected extras rejection")
    } catch let error as PairingException {
        #expect(error.message.contains("再出示邀请"))
    }
}

@Test func redeemRequiresHostId() async throws {
    let transport = ScriptedHTTPTransport { call in
        if call.url.contains("redeem") {
            let body = #"{"device_id":"d1","access_token":"tok","scopes":["conversation.read"]}"#
            return HTTPExchange(status: 200, body: Data(body.utf8))
        }
        let caps = #"{"server_version":"1.0.0","protocol_version":"1.0","minimum_client_version":"1.0","capabilities":[]}"#
        return HTTPExchange(status: 200, body: Data(caps.utf8))
    }
    do {
        _ = try await PairingClient(transport: transport).redeem(
            origin: try HostOrigin.parse("http://10.0.0.2:3080"),
            pairingToken: "ABCD1234"
        )
        Issue.record("expected missing host_id")
    } catch let error as PairingException {
        #expect(error.message.contains("host_id"))
    }
}

@Test func catalogCamelAndSnake() async throws {
    let json = #"{"data":{"projects":[{"id":"p1","name":"App","path":"/a"}],"workspaces":[{"id":"w1","project_id":"p1","name":"main","branch":"main"}],"agents":[{"id":"grok","ready":true,"display_name":"Grok"}]}}"#
    let transport = ScriptedHTTPTransport { _ in
        HTTPExchange(status: 200, body: Data(json.utf8))
    }
    let catalog = try await HostClient(transport: transport).catalog(
        origin: try HostOrigin.parse("http://10.0.0.2:3080"),
        token: "t",
        operationId: "op-catalog"
    )
    #expect(catalog.projects.first?.id == "p1")
    #expect(catalog.workspaces.first?.projectId == "p1")
    #expect(catalog.agents.first?.displayName == "Grok")
}

@Test func listRecentReadsNestedAgent() async throws {
    let json = #"{"data":[{"id":"c1","title":"修配对","agent":{"id":"grok"},"status":"inprogress"}]}"#
    let transport = ScriptedHTTPTransport { _ in
        HTTPExchange(status: 200, body: Data(json.utf8))
    }
    let listed = try await HostClient(transport: transport).listRecent(
        origin: try HostOrigin.parse("http://10.0.0.2:3080"),
        token: "t",
        operationId: "op-list",
        sinceDays: 7,
        projectId: "p1"
    )
    #expect(listed.first?.agentId == "grok")
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    var items: T {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func append(_ item: String) where T == [String] {
        lock.lock(); value.append(item); lock.unlock()
    }
}
