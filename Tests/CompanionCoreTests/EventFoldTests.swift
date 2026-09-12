import Testing
@testable import CompanionCore

@Test func foldsTextDeltasIntoOneRow() {
    let session = TimelineSession()
    session.conversationId = "c1"
    EventFold.apply(session, event: event(1, "user_turn_created", obj(["blocks": .array([obj(["text": .string("Hi")])])])))
    EventFold.apply(session, event: event(2, "assistant_text_delta", obj(["text": .string("Hel"), "message_id": .string("m1")])))
    EventFold.apply(session, event: event(3, "assistant_text_delta", obj(["text": .string("lo"), "message_id": .string("m1")])))
    EventFold.apply(session, event: event(4, "turn_completed", obj([:])))
    let view = session.snapshot()
    #expect(view.rows.filter { $0.kind == "assistant" }.count == 1)
    #expect(view.rows.first { $0.kind == "assistant" }?.body == "Hello")
    #expect(view.inFlightTurnId == nil)
}

@Test func ignoresDuplicateSequence() {
    let session = TimelineSession()
    EventFold.apply(session, event: event(1, "assistant_text_delta", obj(["text": .string("A")])))
    EventFold.apply(session, event: event(1, "assistant_text_delta", obj(["text": .string("B")])))
    #expect(session.rows.count == 1)
    #expect(session.rows[0].body == "A")
    #expect(session.lastSequence == 1)
}

@Test func unknownKindAlwaysPlaceholder() {
    let session = TimelineSession()
    EventFold.apply(session, event: event(8, "brand_new_kind", obj(["x": .string("1")])))
    #expect(session.rows[0].body == "Host 更新了此会话")
    #expect(session.rows[0].kind == "brand_new_kind")
}

@Test func snapshotThenReplayDoesNotDuplicate() {
    let session = TimelineSession()
    EventFold.applySnapshot(
        session,
        through: 3,
        payload: obj([
            "conversation_id": .string("c1"),
            "title": .string("T"),
            "rows": .array([
                obj(["id": .string("asst:t:m1"), "kind": .string("assistant"), "body": .string("Hello")]),
            ]),
        ])
    )
    #expect(session.lastSequence == 3)
    EventFold.apply(session, event: event(1, "assistant_text_delta", obj(["text": .string("Hel"), "message_id": .string("m1")])))
    EventFold.apply(session, event: event(3, "turn_completed", obj([:])))
    #expect(session.rows.filter { $0.kind == "assistant" }.count == 1)
    EventFold.apply(session, event: event(4, "assistant_text_delta", obj(["text": .string("!"), "message_id": .string("m2")])))
    #expect(session.lastSequence == 4)
}

@Test func snapshotClearsStaleInFlight() {
    let session = TimelineSession()
    session.inFlightTurnId = "stale"
    EventFold.applySnapshot(
        session,
        through: 4,
        payload: obj([
            "events": .array([
                obj(["sequence": .number(1), "kind": .string("user_turn_created"), "payload": obj(["turn_id": .string("t1"), "text": .string("hi")])]),
                obj(["sequence": .number(2), "kind": .string("assistant_text_delta"), "payload": obj(["text": .string("ok")])]),
                obj(["sequence": .number(3), "kind": .string("turn_completed"), "payload": obj([:])]),
            ]),
        ])
    )
    #expect(session.inFlightTurnId == nil)
}

@Test func snapshotEventsOnly() {
    let session = TimelineSession()
    EventFold.applySnapshot(
        session,
        through: 3,
        payload: obj([
            "events": .array([
                obj(["sequence": .number(1), "kind": .string("assistant_text_delta"), "payload": obj(["text": .string("Hel"), "message_id": .string("m1")])]),
                obj(["sequence": .number(2), "kind": .string("assistant_text_delta"), "payload": obj(["text": .string("lo"), "message_id": .string("m1")])]),
                obj(["sequence": .number(3), "kind": .string("turn_completed"), "payload": obj([:])]),
            ]),
        ])
    )
    #expect(session.rows.first { $0.kind == "assistant" }?.body == "Hello")
    #expect(session.lastSequence == 3)
}

@Test func permissionBecomesPending() {
    let session = TimelineSession()
    EventFold.apply(
        session,
        event: event(2, "permission_requested", obj([
            "request": obj([
                "id": .string("p1"),
                "tool_name": .string("bash"),
                "options": .array([obj(["option_id": .string("allow-once"), "label": .string("允许一次")])]),
            ]),
        ]))
    )
    let pending = EventFold.pendingItems(session)
    #expect(pending.count == 1)
    #expect(pending[0].id == "p1")
    #expect(!pending[0].options.isEmpty)
}

@Test func interruptedDoesNotResend() {
    let session = TimelineSession()
    EventFold.apply(session, event: event(1, "assistant_text_delta", obj(["text": .string("x")])))
    EventFold.apply(session, event: event(2, "turn_interrupted", obj([:])))
    #expect(session.inFlightTurnId == nil)
    #expect(session.rows.last?.kind == "turn_interrupted")
    #expect(session.notices.last?.action == "retry")
}

@Test func usageMissingStaysMissing() {
    let session = TimelineSession()
    EventFold.apply(session, event: event(1, "usage_updated", obj([:])))
    #expect(session.usageLabel == nil)
}

@Test func serverFrameUnknownDoesNotThrow() {
    let frame = ServerFrameDecoder.decode(#"{"type":"workflow_run","subscription_id":"s"}"#)
    if case .unknown(let type, _) = frame {
        #expect(type == "workflow_run")
    } else {
        Issue.record("expected unknown")
    }
}

@Test func clientFrameAttachEncodes() throws {
    let text = try ClientFrameEncoder.encode(.attach(subscriptionId: "s1", resource: .conversation(id: "c1"), afterSequence: 9))
    #expect(text.contains("attach"))
    #expect(text.contains("c1"))
}

private func event(_ sequence: Int64, _ kind: String, _ payload: JSONValue) -> RemoteEvent {
    RemoteEvent(sequence: sequence, kind: kind, payload: payload)
}

private func obj(_ values: [String: JSONValue]) -> JSONValue { .object(values) }
