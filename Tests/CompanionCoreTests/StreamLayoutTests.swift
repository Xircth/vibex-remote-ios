import Testing
@testable import CompanionCore

@Test func foldsProcessBeforeLastAssistant() {
    let user = TimelineRow(id: "u1", kind: "user", body: "hi", tone: .quiet)
    let tool = TimelineRow(id: "t1", kind: "tool", title: "read", body: "src", tone: .quiet)
    let early = TimelineRow(id: "a0", kind: "assistant", body: "working", tone: .quiet)
    let last = TimelineRow(id: "a1", kind: "assistant", body: "done", tone: .quiet)
    let nodes = layoutStream([user, tool, early, last], options: StreamLayoutOptions(foldProcess: true))
    #expect(nodes.count == 3)
    guard case .user = nodes[0] else { Issue.record("expected user"); return }
    guard case .fold(let prelude) = nodes[1] else { Issue.record("expected fold"); return }
    #expect(prelude.map(\.id) == ["t1", "a0"])
    guard case .assistant(let row) = nodes[2] else { Issue.record("expected assistant"); return }
    #expect(row.id == "a1")
}

@Test func appendsWaitingWhileInFlight() {
    let user = TimelineRow(id: "u1", kind: "user", body: "hi", tone: .quiet)
    let nodes = layoutStream([user], options: StreamLayoutOptions(inFlight: true))
    #expect(nodes.contains { if case .waiting(let compact) = $0 { return compact == false }; return false })
}

@Test func hidesPendingAndFailedTools() {
    let failed = TimelineRow(id: "t1", kind: "tool", title: "x", tone: .stop, toolStatus: "error")
    let pending = TimelineRow(id: "p1", kind: "permission_requested", title: "allow", tone: .hold, pendingKind: .permission, pendingId: "p")
    let nodes = layoutStream([failed, pending], options: StreamLayoutOptions(showFailedTools: false))
    #expect(nodes.isEmpty)
}

@Test func grokUsesBundledImageName() {
    #expect(bundledAgentImageName("grok") == "agent-grok")
    #expect(bundledAgentImageName("Grok Code") == "agent-grok")
    #expect(bundledAgentImageName("claude_code") == "agent-claude")
}

@Test func agentIdentityReadsNestedObject() {
    let nested: [String: JSONValue] = [
        "id": .string("c1"),
        "agent": .object(["id": .string("grok")]),
    ]
    #expect(nested.agentIdentity() == "grok")
    let typed: [String: JSONValue] = ["agent_type": .string("codex")]
    #expect(typed.agentIdentity() == "codex")
}

@Test func compactSummarySkipsGenericMode() {
    let summary = compactSessionConfigSummary(
        modes: [SessionMode(id: "default", name: "Default")],
        currentModeId: "default",
        options: [
            SessionConfigOption(
                key: "model",
                label: "Model",
                category: "model",
                value: "grok",
                choices: [SessionConfigChoice(value: "grok", label: "Grok 4.6")]
            ),
        ]
    )
    #expect(summary == "Grok4.6")
}
