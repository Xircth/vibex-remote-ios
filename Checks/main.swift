import CompanionCore
import Foundation

final class Counter: @unchecked Sendable {
    var failures = 0
}
let counter = Counter()
func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        counter.failures += 1
        fputs("FAIL: \(msg)\n", stderr)
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String) {
    expect(a == b, "\(msg): \(a) != \(b)")
}

do {
    let invitation = try PairingInvitationParser.parse(
        #"vibex-pairing:{"host_id":"h1","preset":"companion","pairing_token":"vbx_pair_abc","reachability":[{"origin":"http://192.168.1.8:3080","kind":"lan"},{"origin":"https://box.ts.net","kind":"tailscale"}]}"#
    )
    expectEqual(invitation.hostId, "h1", "host id")
    expectEqual(invitation.reachability.count, 2, "reachability count")
} catch {
    counter.failures += 1
    fputs("FAIL parse invitation \(error)\n", stderr)
}

do {
    let invitation = try PairingInvitationParser.parse(
        #"{"pairing_token":"tok","reachability":[{"origin":"http://127.0.0.1:3080","kind":"lan"},{"origin":"http://10.0.0.2:3080","kind":"lan"}]}"#
    )
    expectEqual(invitation.reachability.map(\.origin.value), ["http://10.0.0.2:3080"], "drop loopback")
} catch {
    counter.failures += 1
    fputs("FAIL loopback \(error)\n", stderr)
}

do {
    _ = try PairingInvitationParser.parse("http://192.168.1.1:3080")
    counter.failures += 1
    fputs("FAIL expected non-invitation reject\n", stderr)
} catch { }

do {
    _ = try PairingInvitationParser.parseManual(origin: "http://10.0.0.2:3080", pairingToken: "vbx_device_secret")
    counter.failures += 1
    fputs("FAIL expected device token reject\n", stderr)
} catch { }

do {
    _ = try PairingInvitationParser.parse(#"{"pairing_token":"vbx_device_secret","reachability":[{"origin":"http://10.0.0.2:3080","kind":"lan"}]}"#)
    counter.failures += 1
    fputs("FAIL expected scan device token reject\n", stderr)
} catch { }

do {
    let targets = [
        ReachabilityTarget(origin: try HostOrigin.parse("http://192.168.1.20:17891"), kind: "lan"),
        ReachabilityTarget(origin: try HostOrigin.parse("http://47.109.140.92:13630"), kind: "published"),
    ]
    expectEqual(
        OriginOrder.probeOrder(targets: targets, lastSuccess: nil).map(\.value),
        ["http://47.109.140.92:13630", "http://192.168.1.20:17891"],
        "published before lan"
    )
    expectEqual(try HostOrigin.parse("47.109.140.92:13630").value, "http://47.109.140.92:13630", "parse ip")
    expect(try HostOrigin.parse("http://47.109.140.92:13630").isATSBlockedPublicHTTP, "ats public http")
    expect(!(try HostOrigin.parse("http://192.168.1.20:17891").isATSBlockedPublicHTTP), "lan http allowed")
} catch {
    counter.failures += 1
    fputs("FAIL origin \(error)\n", stderr)
}

expect(CompanionScopes.extras(["conversation.read"]).isEmpty, "scopes allow")
expect(CompanionScopes.extras(["plugin.write"]) == ["plugin.write"], "scopes extra")
expect(ConnectionState.online.allowsWrites, "online writes")
expect(!ConnectionState.offline.allowsWrites, "offline no writes")

let session = TimelineSession()
EventFold.apply(session, event: RemoteEvents.make(sequence: 1, kind: "assistant_text_delta", payload: .object(["text": .string("Hel"), "message_id": .string("m1")])))
EventFold.apply(session, event: RemoteEvents.make(sequence: 2, kind: "assistant_text_delta", payload: .object(["text": .string("lo"), "message_id": .string("m1")])))
EventFold.apply(session, event: RemoteEvents.make(sequence: 3, kind: "turn_completed", payload: .object([:])))
expectEqual(session.snapshot().rows.first { $0.kind == "assistant" }?.body, "Hello", "delta merge")
expect(session.inFlightTurnId == nil, "turn complete")

let dup = TimelineSession()
EventFold.apply(dup, event: RemoteEvents.make(sequence: 1, kind: "assistant_text_delta", payload: .object(["text": .string("A")])))
EventFold.apply(dup, event: RemoteEvents.make(sequence: 1, kind: "assistant_text_delta", payload: .object(["text": .string("B")])))
expectEqual(dup.rows.first?.body, "A", "dup sequence")

let unknown = TimelineSession()
EventFold.apply(unknown, event: RemoteEvents.make(sequence: 8, kind: "brand_new_kind", payload: .object(["x": .string("1")])))
expectEqual(unknown.rows.first?.body, "Host 更新了此会话", "unknown kind")

let snap = TimelineSession()
EventFold.applySnapshot(
    snap,
    through: 3,
    payload: .object([
        "rows": .array([.object(["id": .string("a1"), "kind": .string("assistant"), "body": .string("Hello")])]),
    ])
)
expectEqual(snap.lastSequence, 3, "snapshot lastSequence")
EventFold.apply(snap, event: RemoteEvents.make(sequence: 2, kind: "assistant_text_delta", payload: .object(["text": .string("x")])))
expectEqual(snap.rows.filter { $0.kind == "assistant" }.count, 1, "no duplicate after snapshot")

let evSnap = TimelineSession()
EventFold.applySnapshot(
    evSnap,
    through: 2,
    payload: .object([
        "events": .array([
            .object(["sequence": .number(1), "kind": .string("assistant_text_delta"), "payload": .object(["text": .string("Hel"), "message_id": .string("m1")])]),
            .object(["sequence": .number(2), "kind": .string("assistant_text_delta"), "payload": .object(["text": .string("lo"), "message_id": .string("m1")])]),
        ]),
    ])
)
expectEqual(evSnap.rows.first { $0.kind == "assistant" }?.body, "Hello", "events snapshot")
expectEqual(evSnap.lastSequence, 2, "events snapshot seq")

let perm = TimelineSession()
EventFold.apply(
    perm,
    event: RemoteEvents.make(
        sequence: 2,
        kind: "permission_requested",
        payload: .object(["request": .object(["id": .string("p1"), "tool_name": .string("bash")])])
    )
)
expectEqual(EventFold.pendingItems(perm).first?.id, "p1", "pending")

let interrupted = TimelineSession()
EventFold.apply(interrupted, event: RemoteEvents.make(sequence: 1, kind: "assistant_text_delta", payload: .object(["text": .string("x")])))
EventFold.apply(interrupted, event: RemoteEvents.make(sequence: 2, kind: "turn_interrupted", payload: .object([:])))
expect(interrupted.inFlightTurnId == nil, "interrupted clears inflight")
expectEqual(interrupted.notices.last?.action, "retry", "retry notice")

let usage = TimelineSession()
EventFold.apply(usage, event: RemoteEvents.make(sequence: 1, kind: "usage_updated", payload: .object([:])))
expect(usage.usageLabel == nil, "missing usage")

if case .unknown(let type, _) = ServerFrameDecoder.decode(#"{"type":"workflow_run","subscription_id":"s"}"#) {
    expectEqual(type, "workflow_run", "unknown frame")
} else {
    counter.failures += 1
    fputs("FAIL expected unknown frame\n", stderr)
}

do {
    let encoded = try ClientFrameEncoder.encode(.attach(subscriptionId: "s1", resource: .conversation(id: "c1"), afterSequence: 9))
    expect(encoded.contains("attach"), "attach type")
    expect(encoded.contains("c1"), "attach id")
    expect(encoded.contains("after_sequence"), "after_sequence")
    expect(!encoded.contains("token"), "attach has no token")
} catch {
    counter.failures += 1
    fputs("FAIL encode \(error)\n", stderr)
}

let extrasTransport = ScriptedHTTPTransport { call in
    if call.url.contains("redeem") {
        return HTTPExchange(
            status: 200,
            body: Data(#"{"device_id":"d1","access_token":"tok","scopes":["conversation.read","plugin.write"]}"#.utf8)
        )
    }
    return HTTPExchange(status: 500, body: Data())
}
do {
    _ = try await PairingClient(transport: extrasTransport).redeem(
        origin: try HostOrigin.parse("http://10.0.0.2:3080"),
        pairingToken: "ABCD1234"
    )
    counter.failures += 1
    fputs("FAIL expected extras reject\n", stderr)
} catch let error as PairingException {
    expect(error.message.contains("再出示邀请"), "extras copy")
}

let fixtureRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("docs/fixtures/companion-core")
if let data = try? Data(contentsOf: fixtureRoot.appendingPathComponent("fold-snapshot-replay.json")),
   let json = try? JSONValue.parse(data).asObject() {
    let session = TimelineSession()
    EventFold.applySnapshot(session, through: json.longOrNull("through_sequence") ?? 0, payload: json["payload"] ?? .null)
    for item in json.arrOrNull("replay") {
        guard let obj = item.asObject(), let sequence = obj.longOrNull("sequence"), let kind = obj.textOrNull("kind") else { continue }
        EventFold.apply(session, event: RemoteEvents.make(sequence: sequence, kind: kind, payload: obj["payload"] ?? .null))
    }
    expectEqual(session.lastSequence, 3, "fixture replay lastSequence")
    expectEqual(session.rows.filter { $0.kind == "assistant" }.count, 1, "fixture replay one assistant")
}

if let data = try? Data(contentsOf: fixtureRoot.appendingPathComponent("fold-snapshot-events.json")),
   let json = try? JSONValue.parse(data).asObject() {
    let session = TimelineSession()
    EventFold.applySnapshot(session, through: json.longOrNull("through_sequence") ?? 0, payload: json["payload"] ?? .null)
    expectEqual(session.snapshot().rows.first { $0.kind == "assistant" }?.body, "Hello", "fixture events body")
    expectEqual(session.lastSequence, 3, "fixture events lastSequence")
}

let cfg = TimelineSession()
EventFold.apply(
    cfg,
    event: RemoteEvents.make(
        sequence: 4,
        kind: "session_config_options_updated",
        payload: .object([
            "options": .array([.object(["key": .string("model"), "label": .string("Model"), "value": .string("fast")])]),
        ])
    )
)
expectEqual(cfg.snapshot().sessionConfig.first?.key, "model", "session config fold")

let del = TimelineSession()
EventFold.apply(
    del,
    event: RemoteEvents.make(
        sequence: 1,
        kind: "delegation_started",
        payload: .object(["delegation": .object(["delegation_id": .string("d1"), "task_preview": .string("子任务"), "child_conversation_id": .string("c2")])])
    )
)
expectEqual(del.rows.first?.title, "委派", "delegation row")

do {
    let user = TimelineRow(id: "u1", kind: "user", body: "hi", tone: .quiet)
    let tool = TimelineRow(id: "t1", kind: "tool", title: "read", body: "src", tone: .quiet, toolKind: "read")
    let assistant = TimelineRow(id: "a1", kind: "assistant", body: "done", tone: .quiet)
    let folded = layoutStream([user, tool, assistant], options: StreamLayoutOptions(foldProcess: true))
    expectEqual(folded.count, 3, "fold turn node count")
    if case .user = folded[0] { } else { expect(false, "fold first user") }
    if case .fold(let rows) = folded[1] { expectEqual(rows.map(\.id), ["t1"], "fold prelude tools") } else { expect(false, "fold process node") }
    if case .assistant(let row) = folded[2] { expectEqual(row.body, "done", "fold keeps last assistant") } else { expect(false, "fold last assistant") }

    let waiting = layoutStream([user], options: StreamLayoutOptions(foldProcess: true, inFlight: true))
    expect(waiting.contains { if case .waiting = $0 { return true }; return false }, "waiting while in flight")

    let summary = compactSessionConfigSummary(
        modes: [SessionMode(id: "agent", name: "Grok4.6")],
        currentModeId: "agent",
        options: [SessionConfigOption(key: "effort", label: "Effort", category: "thought", value: "high", choices: [SessionConfigChoice(value: "high", label: "High")])]
    )
    expectEqual(summary, "Grok4.6 · High", "config summary")
}

await runtimeChecks(counter)

if counter.failures == 0 {
    print("CompanionCoreCheck: all passed")
    exit(0)
} else {
    fputs("CompanionCoreCheck: \(counter.failures) failed\n", stderr)
    exit(1)
}

@MainActor
func runtimeChecks(_ counter: Counter) async {
    func expect(_ cond: Bool, _ msg: String) {
        if !cond {
            counter.failures += 1
            fputs("FAIL: \(msg)\n", stderr)
        }
    }
    let profiles = MemoryProfileStore()
    try? profiles.save(
        StoredState(
            profiles: [
                HostProfile(
                    hostId: "h1",
                    name: "h1",
                    reachability: [StoredReachability(origin: "http://10.0.0.2:3080", kind: "lan")],
                    lastSuccessfulOrigin: "http://10.0.0.2:3080",
                    selectedProjectId: nil,
                    deviceId: "d0",
                    grantedScopes: Array(CompanionScopes.allowed)
                ),
            ],
            selectedHostId: "h1",
            sinceDays: 3,
            appearance: "system",
            accent: 8,
            monitor: false,
            thinking: "hidden",
            showFailedTools: false,
            toolsCollapsed: true,
            messagesCollapsed: true
        )
    )
    let credentials = MemoryCredentialStore()
    try? credentials.put(hostId: "h1", token: "old-token")
    let redeemCalled = Counter()
    let http = ScriptedHTTPTransport { call in
        if call.url.contains("redeem") {
            redeemCalled.failures += 1
            return HTTPExchange(status: 500, body: Data())
        }
        if call.url.contains("capabilities") {
            let body = #"{"server_version":"1.2.0","protocol_version":"1.0","minimum_client_version":"1.0","capabilities":["conversation"],"host_id":"h1"}"#
            return HTTPExchange(status: 200, body: Data(body.utf8))
        }
        if call.url.contains("conversation_catalog") || call.url.contains("conversation_list_recent") {
            return HTTPExchange(status: 200, body: Data(#"{"data":{"projects":[],"workspaces":[],"agents":[]}}"#.utf8))
        }
        return HTTPExchange(status: 200, body: Data(#"{"data":{}}"#.utf8))
    }
    let events = MemoryEventTransport()
    let runtime = CompanionRuntime(
        http: http,
        credentials: credentials,
        profiles: profiles,
        offline: MemoryOfflineStore(),
        events: events
    )
    do {
        try await runtime.pair(
            fromRaw: #"vibex-pairing:{"host_id":"h1","pairing_token":"vbx_pair_abc","reachability":[{"origin":"https://box.ts.net","kind":"tailscale"},{"origin":"http://10.0.0.2:3080","kind":"lan"}]}"#
        )
        expect(redeemCalled.failures == 0, "existing host skips redeem")
        expect(runtime.snapshot.notice == "已更新地址", "merge notice")
        expect(runtime.snapshot.profiles.count == 1, "single profile")
        expect(runtime.snapshot.profiles[0].reachability.contains(where: { $0.origin == "https://box.ts.net" }), "merged origin")
    } catch {
        counter.failures += 1
        fputs("FAIL merge pair \(error)\n", stderr)
    }

    expect(events.connectedOrigin?.contains("token=") != true, "ws url has no token")
    expect(events.protocols.contains(where: { $0.hasPrefix("vibex.token.") }), "ws offers token subprotocol")
    expect(events.protocols.contains("vibex.v1"), "ws offers vibex.v1")

    runtime.setAccent(1)
    expect(runtime.snapshot.accent == 1, "accent persist field")
    expect(!ConnectionState.recovering.allowsWrites, "recovering no writes")
    expect(ConnectionState.connecting.chipLabel(profileName: "x", lastSync: nil) == "正在连接", "chip connecting")
    expect(ConnectionState.online.chipLabel(profileName: "desk", lastSync: nil) == "在线", "chip online")
}
